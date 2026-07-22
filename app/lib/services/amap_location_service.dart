import 'dart:async';
import 'dart:collection';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:flutter/widgets.dart';
import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'motion_detector.dart';

/// 高德定位服务 — 替代 Geolocator 方案
///
/// 使用高德 AMapLocationClient 的原生定位能力：
/// - 原生 GCJ-02 坐标，无需手动转换
/// - 中国区GPS优化，稳定性更好
/// - 与 AMapWidget 使用同一套定位框架
///
/// 功能与旧版 LocationService 保持一致：
/// - 活动状态机（MOVING/UNCERTAIN/STATIONARY）
/// - 加速度传感器辅助判断静止与漂移
/// - 自适应上传频率（12秒/30秒/5分钟）
/// - 缓冲平均 + 3点中值滤波 + 加速度验证三重防漂移
class AmapLocationService {
  static final AmapLocationService _instance = AmapLocationService._internal();
  factory AmapLocationService() => _instance;

  final ApiService _api = ApiService();
  final MotionDetector _motion = MotionDetector();

  // ─── 当前位置 ───
  AMapLocation? _currentLocation;
  AMapLocation? _lastKnownLocation;
  final List<AMapLocation> _recentLocations = [];
  StreamSubscription<Map<String, Object?>>? _locationSubscription;
  Timer? _uploadTimer;
  Timer? _motionCheckTimer;
  Timer? _gpsWatchdog;
  DateTime? _lastGpsTime;
  bool _isRunning = false;
  bool _isInitialized = false;

  // ─── 位置缓存队列 ───
  final Queue<_PositionRecord> _positionBuffer = Queue();
  static const int _buffersMoving = 3;
  static const int _buffersUncertain = 3;
  static const int _buffersStationary = 1;

  // ─── GPS丢失标记 ───
  bool _gpsLost = false;
  DateTime? _gpsLostSince;

  // ─── 性能统计 ───
  int _totalPositions = 0;
  int _rejectedPositions = 0;
  double _bestAccuracy = 999;

  // ─── 回调 ───
  void Function(double lat, double lng, double accuracy, double? speed)?
      onLocationChanged;
  void Function(String error)? onError;
  void Function(String stateName, int interval)? onStateChanged;

  AmapLocationService._internal();

  double? get currentLat => _currentLocation?.latitude;
  double? get currentLng => _currentLocation?.longitude;
  double? get currentAccuracy => _currentLocation?.accuracy;
  bool get isRunning => _isRunning;
  int get totalPositions => _totalPositions;
  int get rejectedPositions => _rejectedPositions;
  double get bestAccuracy => _bestAccuracy;
  MotionState get motionState => _motion.state;
  bool get isGpsLost => _gpsLost;

  int get _currentBufferSize {
    switch (_motion.state) {
      case MotionState.moving:
        return _buffersMoving;
      case MotionState.uncertain:
        return _buffersUncertain;
      case MotionState.stationary:
        return _buffersStationary;
    }
  }

  // ─── Haversine 公式 ───
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    return _haversineKm(lat1, lng1, lat2, lng2) * 1000;
  }

  /// 初始化高德定位SDK
  Future<bool> initSdk() async {
    if (_isInitialized) return true;
    try {
      // 设置API Key（通常已在 AndroidManifest.xml / Info.plist 中配置）
      // AMapLocationClient.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey);
      // 注：AMap Flutter Location 3.x 通常从原生层读取key
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[AmapLocation] SDK初始化失败: $e');
      return false;
    }
  }

  /// 启动定位追踪
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    // 1. 初始化SDK
    if (!_isInitialized) {
      final ok = await initSdk();
      if (!ok) {
        onError?.call('高德定位SDK初始化失败');
        return false;
      }
    }

    // 2. 启动加速度传感器
    await _motion.start();

    // 3. 监听状态变化
    _motion.onStateChanged = (state) {
      _rescheduleUploadTimer();
      onStateChanged?.call(_motion.stateName, _motion.uploadInterval);
    };

    // 4. 订阅高德定位流
    try {
      _locationSubscription = AMapLocationClient.getLocationStream().listen(
        _onLocation,
        onError: (error) {
          debugPrint('[AmapLocation] 定位流错误: $error');
          onError?.call('定位流错误: $error');
        },
      );
    } catch (e) {
      debugPrint('[AmapLocation] 订阅定位流失败: $e');
      onError?.call('启动定位失败: $e');
      return false;
    }

    // 5. 启动高德定位客户端
    AMapLocationClient.startLocation(AMapLocationOption(
      locationMode: AMapLocationMode.hightAccuracy,
      onceLocation: false,
      interval: 2000, // 2秒定位间隔
      allowsBackgroundLocation: true,
      pausesLocationUpdatesAutomatically: false,
    ));

    _lastGpsTime = DateTime.now();

    // 6. 启动上传定时器
    _scheduleUploadTimer();

    // 7. 定期检查运动状态
    _motionCheckTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkMotionState(),
    );

    // 8. GPS看门狗
    _gpsWatchdog = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkGpsHealth(),
    );

    _isRunning = true;
    debugPrint('[AmapLocation] 定位追踪已启动');
    return true;
  }

  /// 停止定位追踪
  void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _motionCheckTimer?.cancel();
    _motionCheckTimer = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _positionBuffer.clear();
    _motion.stop();
    _recentLocations.clear();
    _isRunning = false;
    _currentLocation = null;
    _gpsLost = false;
    _gpsLostSince = null;
    _lastKnownLocation = null;
    _lastGpsTime = null;

    AMapLocationClient.stopLocation();
    debugPrint('[AmapLocation] 定位追踪已停止');
  }

  // ============================================================
  //  高德定位数据处理
  // ============================================================

  void _onLocation(Map<String, Object?> locationData) {
    try {
      _totalPositions++;

      final location = AMapLocation.fromJson(locationData);
      if (location == null) return;

      _lastGpsTime = DateTime.now();

      // 精度校验
      final accuracy = location.accuracy ?? 999;
      if (accuracy > AppConfig.maxAcceptableAccuracy) {
        _rejectedPositions++;
        _onGpsLoss();
        return;
      }

      // GPS恢复
      if (_gpsLost) {
        _gpsLost = false;
        _gpsLostSince = null;
      }

      if (accuracy < _bestAccuracy) {
        _bestAccuracy = accuracy;
      }

      _currentLocation = location;
      _lastKnownLocation = location;

      // ─── 3点滑动中值滤波 ───
      _recentLocations.add(location);
      if (_recentLocations.length > 3) _recentLocations.removeAt(0);

      if (_recentLocations.length == 3) {
        final p2 = _recentLocations[1];
        if (_isDriftPoint(_recentLocations[0], p2, _recentLocations[2])) {
          final speed = location.speed ?? 0;
          final disp = _motion.calculateDisplacement(
            location.latitude,
            location.longitude,
          );
          final bool isReal =
              _motion.hasAccelActivity || disp > AppConfig.cumulativeMoveThreshold;
          if (speed < 0.5 && !isReal) {
            _removeFromBuffer(p2.latitude, p2.longitude);
            _recentLocations.removeAt(1);
            _rejectedPositions++;
          }
        }
      }

      // 加入缓冲区
      _addToBuffer(location);

      // 更新运动状态
      _updateMotionState(location);

      // 对外回调
      onLocationChanged?.call(
        location.latitude,
        location.longitude,
        accuracy,
        location.speed,
      );
    } catch (e) {
      debugPrint('[AmapLocation] 定位数据处理异常: $e');
    }
  }

  void _onGpsLoss() {
    if (!_gpsLost) {
      _gpsLost = true;
      _gpsLostSince = DateTime.now();
      if (_currentLocation != null) {
        onError?.call('GPS信号弱，定位精度低');
      }
    }
  }

  bool _isDriftPoint(AMapLocation p1, AMapLocation p2, AMapLocation p3) {
    final d12 = _haversineKm(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
    final d23 = _haversineKm(p2.latitude, p2.longitude, p3.latitude, p3.longitude);
    final d13 = _haversineKm(p1.latitude, p1.longitude, p3.latitude, p3.longitude);
    return d12 > AppConfig.driftMaxDistKm &&
        d23 > AppConfig.driftMaxDistKm &&
        d13 < AppConfig.driftSkipDistKm;
  }

  void _removeFromBuffer(double lat, double lng) {
    _positionBuffer.removeWhere((r) =>
        (r.lat - lat).abs() < 0.0001 && (r.lng - lng).abs() < 0.0001);
  }

  // ============================================================
  //  活动状态机
  // ============================================================

  void _updateMotionState(AMapLocation loc) {
    final displacement = _motion.calculateDisplacement(loc.latitude, loc.longitude);
    _motion.updateState(
      speed: loc.speed,
      gpsLost: false,
      cumulativeDisplacement: displacement,
      currentLat: loc.latitude,
      currentLng: loc.longitude,
    );
  }

  void _checkMotionState() {
    if (!_isRunning) return;
    if (_currentLocation == null) return;
    final displacement = _motion.calculateDisplacement(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
    );
    _motion.updateState(
      speed: _currentLocation!.speed,
      gpsLost: _gpsLost,
      cumulativeDisplacement: displacement,
      currentLat: _currentLocation!.latitude,
      currentLng: _currentLocation!.longitude,
    );
  }

  /// GPS看门狗：60秒无位置则重启
  void _checkGpsHealth() {
    if (!_isRunning) return;
    if (_lastGpsTime == null) return;
    final elapsed = DateTime.now().difference(_lastGpsTime!);
    if (elapsed.inSeconds < 60) return;

    debugPrint('[AmapLocation] GPS流已静默${elapsed.inSeconds}秒，正在重启...');
    onError?.call('GPS流超时，正在重启...');

    _locationSubscription?.cancel();
    _locationSubscription = null;
    AMapLocationClient.stopLocation();

    try {
      _locationSubscription = AMapLocationClient.getLocationStream().listen(
        _onLocation,
        onError: (error) {
          onError?.call('定位流错误: $error');
        },
      );
      AMapLocationClient.startLocation(AMapLocationOption(
        locationMode: AMapLocationMode.hightAccuracy,
        onceLocation: false,
        interval: 2000,
        allowsBackgroundLocation: true,
        pausesLocationUpdatesAutomatically: false,
      ));
      _lastGpsTime = DateTime.now();
      debugPrint('[AmapLocation] GPS流已重启');
    } catch (e) {
      debugPrint('[AmapLocation] GPS流重启失败: $e');
    }
  }

  // ============================================================
  //  缓存 & 上报
  // ============================================================

  void _addToBuffer(AMapLocation loc) {
    _positionBuffer.add(_PositionRecord(
      lat: loc.latitude,
      lng: loc.longitude,
      accuracy: loc.accuracy ?? 999,
      speed: loc.speed,
      timestamp: loc.timestamp ?? DateTime.now().millisecondsSinceEpoch,
    ));

    if (_positionBuffer.length >= _currentBufferSize) {
      _flushBuffer();
    }
  }

  Future<void> _flushBuffer() async {
    if (_positionBuffer.isEmpty) return;

    final batch = _positionBuffer.toList();
    _positionBuffer.clear();
    final last = batch.last;

    if (batch.length == 1) {
      try {
        await _api.post(AppConfig.apiReportLocation, data: {
          'lng': last.lng,
          'lat': last.lat,
          'accuracy': last.accuracy,
          'speed': last.speed ?? 0,
          'timestamp': last.timestamp,
          'batch_size': 1,
        });
      } catch (_) {}
    } else {
      final avgLat = batch.map((p) => p.lat).reduce((a, b) => a + b) / batch.length;
      final avgLng = batch.map((p) => p.lng).reduce((a, b) => a + b) / batch.length;
      final avgAccuracy =
          batch.map((p) => p.accuracy).reduce((a, b) => a + b) / batch.length;

      try {
        await _api.post(AppConfig.apiReportLocation, data: {
          'lng': avgLng,
          'lat': avgLat,
          'accuracy': avgAccuracy,
          'speed': last.speed ?? 0,
          'timestamp': last.timestamp,
          'batch_size': batch.length,
        });
      } catch (_) {}
    }

    // 围栏检测
    try {
      await _api.post('/api/v1/fences/auto-check', data: {
        'lat': _currentLocation?.latitude ?? last.lat,
        'lng': _currentLocation?.longitude ?? last.lng,
      });
    } catch (_) {}
  }

  // ============================================================
  //  定时器管理
  // ============================================================

  void _rescheduleUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _scheduleUploadTimer();
  }

  void _scheduleUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(
      Duration(seconds: _motion.uploadInterval),
      (_) => _flushBuffer(),
    );
  }
}

/// 位置缓存记录
class _PositionRecord {
  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final int timestamp;

  const _PositionRecord({
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.speed,
    required this.timestamp,
  });
}

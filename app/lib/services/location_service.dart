import 'dart:async';
import 'dart:collection';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'motion_detector.dart';
import '../utils/geo_convert.dart';

/// 定位服务 v2 — 三信号融合版
///
/// 加速度传感器 + GPS速度 + GPS位置 → 轨迹平滑、自适应频率、静止降频
///
/// 改进（v2）：
///   - 活动状态机（MOVING/UNCERTAIN/STATIONARY）
///   - 加速度传感器辅助判断静止与漂移
///   - 自适应上传频率（12秒/30秒/5分钟）
///   - GPS丢失时不产生假点，标记精度异常
///   - 缓冲平均 + 3点中值滤波 + 加速度验证三重防漂移
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  final MotionDetector _motion = MotionDetector();

  // ─── 当前位置 ───
  Position? _currentPosition;
  Position? _lastKnownPosition; // GPS丢失时保留的最后有效位置
  final List<Position> _recentPositions = [];
  StreamSubscription<Position>? _positionStream;
  Timer? _uploadTimer;
  Timer? _motionCheckTimer; // 定期检查静止基准点位移
+ Timer? _gpsWatchdog;      // GPS健康看门狗：超时自动重启流
+ DateTime? _lastGpsTime;   // 上次收到GPS位置的时间
  bool _isRunning = false;

  // ─── 位置缓存队列 ───
  final Queue<_PositionRecord> _positionBuffer = Queue();
  static const int _buffersMoving = 3;     // MOVING: 3条平均
  static const int _buffersUncertain = 3;
  static const int _buffersStationary = 1;  // 静止: 单点

  // ─── GPS丢失标记 ───
  bool _gpsLost = false;
  DateTime? _gpsLostSince;

  // ─── 性能统计 ───
  int _totalPositions = 0;
  int _rejectedPositions = 0;
  double _bestAccuracy = 999;

  // ─── 回调 ───
  void Function(double lat, double lng, double accuracy, double? speed)? onLocationChanged;
  void Function(String error)? onError;
  void Function(String stateName, int interval)? onStateChanged; // 状态/频率变化回调

  LocationService._internal();

  // ─── Haversine 公式计算两点距离（km） ───
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    return _haversineKm(lat1, lng1, lat2, lng2) * 1000;
  }

  // ─── 访问器 ───
  double? get currentLat => _currentPosition?.latitude;
  double? get currentLng => _currentPosition?.longitude;
  double? get currentAccuracy => _currentPosition?.accuracy;
  Position? get currentPosition => _currentPosition;
  bool get isRunning => _isRunning;
  int get totalPositions => _totalPositions;
  int get rejectedPositions => _rejectedPositions;
  double get bestAccuracy => _bestAccuracy;
  MotionState get motionState => _motion.state;
  bool get isGpsLost => _gpsLost;

  /// 当前使用的缓冲区大小
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

  // ============================================================
  //  启动/停止定位
  // ============================================================

  Future<bool> startTracking() async {
    if (_isRunning) return true;

    // 1. 检查定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      onError?.call('定位权限被拒绝');
      return false;
    }

    // 2. 检查GPS
    final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isGpsEnabled) {
      onError?.call('请开启GPS定位');
      return false;
    }

    // 3. 启动加速度传感器
    await _motion.start();

    // 4. 监听状态变化 → 调整上传定时器
    _motion.onStateChanged = (state) {
      _rescheduleUploadTimer();
      onStateChanged?.call(_motion.stateName, _motion.uploadInterval);
    };

    // 5. 获取一次高精度GPS位置
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
      if (pos != null && pos.accuracy < AppConfig.maxAcceptableAccuracy) {
        final (gcjLat, gcjLng) = wgs84ToGcj02(pos.latitude, pos.longitude);
        _currentPosition = _buildConvertedPosition(pos, gcjLat, gcjLng);
        _lastKnownPosition = _currentPosition;
        _motion.resetStillBase(_currentPosition!.latitude, _currentPosition!.longitude);
        _gpsLost = false;
      }
    } catch (_) {}

    // 6. 持续监听位置变化
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      _onGpsPosition,
      onError: (error) {
        onError?.call('定位流错误: $error');
      },
    );

    // 7. 启动上传定时器（初始MOVING频率）
    _scheduleUploadTimer();

    // 8. 定期检查累计位移（静止时确保基准点准确）
    _motionCheckTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkMotionState(),
    );

+    // 9. GPS健康看门狗：60秒无位置数据则重启GPS流
+    _gpsWatchdog = Timer.periodic(
+      const Duration(seconds: 30),
+      (_) => _checkGpsHealth(),
+    );

    _isRunning = true;
    return true;
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _motionCheckTimer?.cancel();
    _motionCheckTimer = null;
+   _gpsWatchdog?.cancel();
+   _gpsWatchdog = null;
    _positionBuffer.clear();
    _motion.stop();
    _recentPositions.clear();
    _isRunning = false;
    _currentPosition = null;
    _gpsLost = false;
    _gpsLostSince = null;
    _lastKnownPosition = null;
  }

  // ============================================================
  //  GPS数据处理
  // ============================================================

  void _onGpsPosition(Position position) {
    try {
      _totalPositions++;

      // 精度校验
      if (position.accuracy > AppConfig.maxAcceptableAccuracy) {
        _rejectedPositions++;
        _onGpsLoss(position);
        return;
      }

      // GPS恢复
      if (_gpsLost) {
        _gpsLost = false;
        _gpsLostSince = null;
      }
+     _lastGpsTime = DateTime.now();

      // WGS-84 → GCJ-02 转换
      final (gcjLat, gcjLng) = wgs84ToGcj02(position.latitude, position.longitude);
      final converted = _buildConvertedPosition(position, gcjLat, gcjLng);

      if (converted.accuracy < _bestAccuracy) {
        _bestAccuracy = converted.accuracy;
      }

      _currentPosition = converted;
      _lastKnownPosition = converted;

      // ─── 3点滑动中值滤波（漂移检测） ───
      _recentPositions.add(converted);
      if (_recentPositions.length > 3) _recentPositions.removeAt(0);

      if (_recentPositions.length == 3) {
        final p2 = _recentPositions[1];

        // 检查P2是否为孤立漂移点
        if (_isDriftPoint(_recentPositions[0], p2, _recentPositions[2])) {
          // 加速度+累计位移验证：是真移动还是漂移
          final gpsSpeed = position.speed ?? 0;
          final disp = _motion.calculateDisplacement(
            converted.latitude, converted.longitude,
          );
          final bool isReal = _motion.hasAccelActivity ||
              disp > AppConfig.cumulativeMoveThreshold;
          if (gpsSpeed < 0.5 && !isReal) {
            // 真漂移：移除并计数
            _removeFromBuffer(p2.latitude, p2.longitude);
            _recentPositions.removeAt(1);
            _rejectedPositions++;
          }
        }
      }

      // 加入缓冲区
      _addToBuffer(converted);

      // 更新活动状态机
      _updateMotionState(converted);

      // 对外回调
      onLocationChanged?.call(
        converted.latitude,
        converted.longitude,
        converted.accuracy,
        converted.speed,
      );
    } catch (e) {
      debugPrint('[LocationService] GPS数据处理异常: $e');
    }
  }

  /// GPS精度超标时处理 — 记录丢失状态但不产生假点
  void _onGpsLoss(Position lastPosition) {
    if (!_gpsLost) {
      _gpsLost = true;
      _gpsLostSince = DateTime.now();

      // 保持最后已知位置，但标记精度异常
      if (_currentPosition != null) {
        // 不产生新点，只标记状态
        onError?.call('GPS信号弱，定位精度低');
      }
    }
  }

  /// 判断是否为孤立漂移点
  bool _isDriftPoint(Position p1, Position p2, Position p3) {
    final d12 = _haversineKm(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
    final d23 = _haversineKm(p2.latitude, p2.longitude, p3.latitude, p3.longitude);
    final d13 = _haversineKm(p1.latitude, p1.longitude, p3.latitude, p3.longitude);
    return d12 > AppConfig.driftMaxDistKm &&
           d23 > AppConfig.driftMaxDistKm &&
           d13 < AppConfig.driftSkipDistKm;
  }

  /// 从缓冲区移除指定坐标的点
  void _removeFromBuffer(double lat, double lng) {
    _positionBuffer.removeWhere((r) =>
        (r.lat - lat).abs() < 0.0001 &&
        (r.lng - lng).abs() < 0.0001);
  }

  // ============================================================
  //  活动状态机更新
  // ============================================================

  void _updateMotionState(Position pos) {
    final displacement = _motion.calculateDisplacement(
      pos.latitude, pos.longitude,
    );
    _motion.updateState(
      speed: pos.speed,
      gpsLost: false,
      cumulativeDisplacement: displacement,
      currentLat: pos.latitude,
      currentLng: pos.longitude,
    );
  }

  /// 定期检查（不依赖GPS更新的场景）
  void _checkMotionState() {
    if (_currentPosition == null) return;
    final displacement = _motion.calculateDisplacement(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    _motion.updateState(
      speed: _currentPosition!.speed,
      gpsLost: _gpsLost,
      cumulativeDisplacement: displacement,
      currentLat: _currentPosition!.latitude,
      currentLng: _currentPosition!.longitude,
    );
  }

+ /// GPS健康检查：如果60秒内没有收到位置，自动重启GPS流
+ void _checkGpsHealth() {
+   if (_lastGpsTime == null) return;
+   final elapsed = DateTime.now().difference(_lastGpsTime!);
+   if (elapsed.inSeconds < 60) return; // 还在正常接收
+   
+   debugPrint('[LocationService] GPS流已静默${elapsed.inSeconds}秒，正在重启...');
+   onError?.call('GPS流超时，正在重启...');
+   
+   // 取消旧流
+   _positionStream?.cancel();
+   _positionStream = null;
+   
+   // 重新创建订阅
+   try {
+     _positionStream = Geolocator.getPositionStream(
+       locationSettings: const LocationSettings(
+         accuracy: LocationAccuracy.bestForNavigation,
+         distanceFilter: 0,
+       ),
+     ).listen(
+       _onGpsPosition,
+       onError: (error) {
+         onError?.call('定位流错误: $error');
+       },
+     );
+     debugPrint('[LocationService] GPS流已重启');
+     _lastGpsTime = DateTime.now(); // 防止重复重启
+   } catch (e) {
+     debugPrint('[LocationService] GPS流重启失败: $e');
+   }
+ }

  // ============================================================
  //  缓存 & 上报
  // ============================================================

  void _addToBuffer(Position pos) {
    _positionBuffer.add(_PositionRecord(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      speed: pos.speed,
      timestamp: pos.timestamp.millisecondsSinceEpoch,
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
      // 静止模式：直接上报单点
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
      // 移动/不确定：取均值平滑
      final avgLat = batch.map((p) => p.lat).reduce((a, b) => a + b) / batch.length;
      final avgLng = batch.map((p) => p.lng).reduce((a, b) => a + b) / batch.length;
      final avgAccuracy = batch.map((p) => p.accuracy).reduce((a, b) => a + b) / batch.length;

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
        'lat': _currentPosition?.latitude ?? last.lat,
        'lng': _currentPosition?.longitude ?? last.lng,
      });
    } catch (_) {}
  }

  // ============================================================
  //  上传定时器管理
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

  // ============================================================
  //  工具
  // ============================================================

  Position _buildConvertedPosition(Position pos, double gcjLat, double gcjLng) {
    return Position(
      latitude: gcjLat,
      longitude: gcjLng,
      timestamp: pos.timestamp,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      heading: pos.heading,
      speed: pos.speed,
      speedAccuracy: pos.speedAccuracy,
      altitudeAccuracy: pos.altitudeAccuracy,
      headingAccuracy: pos.headingAccuracy,
    );
  }

  Future<Position?> getLastKnownPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        _currentPosition = pos;
      }
      return pos;
    } catch (_) {
      return _currentPosition;
    }
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

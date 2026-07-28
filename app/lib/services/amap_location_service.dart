import 'dart:async';
import 'dart:collection';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'motion_detector.dart';
import 'background_location_service.dart';
import 'location_uploader.dart';
import '../models/location_point.dart';
import '../utils/geo_convert.dart' show haversineKm;

/// 高德定位服务 — 使用原生ForegroundService的AMapLocationClient
///
/// # 生命周期
/// 1. startTracking() → 启动定位追踪
///    - 检查/请求定位权限
///    - 启动加速度传感器（MotionDetector）检测运动状态
///    - 注册原生 ForegroundService 回调接收 GPS 数据
///    - 初始化文件缓存上传器（LocationUploader）
///    - 启动原生 ForegroundService（含 AMapLocationClient + WakeLock）
///    - 启动上传定时器、运动状态检查、GPS 看门狗、隧道 URL 轮询
/// 2. 运行中：通过 _onLocation 处理定位数据管道
///    - 精度校验 → 3点滑动中值滤波 → 漂移检测 → 缓冲区排队 → 批量上传
/// 3. stopTracking() → 停止定位追踪
///    - 取消所有定时器，清空缓冲区，停止 MotionDetector 和 ForegroundService
///
/// 数据流：
/// 原生ForegroundService (AMapLocationClient) → MethodChannel → Flutter
/// 
/// 隧道刷新：每15分钟轮询 /api/v1/tunnel 获取最新隧道URL并自动替换
/// 
/// 注意：不再使用 Flutter AMap 插件的 _locationPlugin，
/// 避免同一进程两个AMapLocationClient实例冲突。
class AmapLocationService {
  static final AmapLocationService _instance = AmapLocationService._internal();
  factory AmapLocationService() => _instance;

  final ApiService _api = ApiService();
  final MotionDetector _motion = MotionDetector();

  // ─── 当前位置 ───
  Map<String, Object>? _currentLocation;
  final List<Map<String, Object>> _recentLocations = [];
  Timer? _uploadTimer;
  Timer? _motionCheckTimer;
  Timer? _gpsWatchdog;
  Timer? _tunnelRefreshTimer; // 隧道URL轮询
  DateTime? _lastGpsTime;
  bool _isRunning = false;

  // ─── GPS看门狗重启保护 ───
  int _gpsRestartCount = 0;
  DateTime? _gpsRestartResetTime;
  static const int _maxGpsRestarts = 3;        // 每小时最多重建3次
  /// GPS看门狗 — 重建ForegroundService延迟（防竞态）
  static const Duration _gpsRestartDelay = Duration(milliseconds: 500);
  static const Duration _gpsRestartWindow = Duration(hours: 1);

  // ─── 位置缓存队列 ───
  final Queue<_PositionRecord> _positionBuffer = Queue();
  static const int _buffersMoving = 3;
  static const int _buffersUncertain = 3;
  static const int _buffersStationary = 1;

  // ─── GPS丢失标记 ───
  bool _gpsLost = false;

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

  double? get currentLat =>
      (_currentLocation?['latitude'] as num?)?.toDouble();
  double? get currentLng =>
      (_currentLocation?['longitude'] as num?)?.toDouble();
  double? get currentAccuracy =>
      (_currentLocation?['accuracy'] as num?)?.toDouble();
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

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    return haversineKm(lat1, lng1, lat2, lng2);
  }

  /// 启动高德定位追踪
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    // 0. 检查定位权限
    var locStatus = await Permission.location.status;
    if (locStatus.isDenied) {
      locStatus = await Permission.location.request();
      if (locStatus.isDenied) {
        onError?.call('定位权限被拒绝，请在设置中开启');
        return false;
      }
    }
    if (locStatus.isPermanentlyDenied) {
      onError?.call('定位权限已被永久拒绝，请在设置中手动开启');
      return false;
    }
    // 后台定位权限（Android 10+）
    if (await Permission.locationAlways.status.isDenied) {
      final bg = await Permission.locationAlways.request();
      if (bg.isDenied) {
        debugPrint('[AmapLoc] 后台定位权限未授予，后台定位功能可能受限');
      }
    }

    // 1. 先绑定onStateChanged再启动加速度传感器（避免初始状态丢失）
    _motion.onStateChanged = (state) {
      _rescheduleUploadTimer();
      onStateChanged?.call(_motion.stateName, _motion.uploadInterval);

      // 状态变化时动态调整GPS采集间隔
      if (state == MotionState.stationary) {
        // 静止 → 60秒采一次（省电）
        setNativeGpsInterval(AppConfig.stationaryGpsIntervalMs);
      } else {
        // 移动/不确定 → 3秒采一次（精细轨迹）
        setNativeGpsInterval(AppConfig.movingGpsIntervalMs);
      }
    };
    await _motion.start();

    // 3. 注册原生ForegroundService回调（替代Flutter AMap插件）
    setupNativeLocationCallback();
    onNativeLocationUpdate = (lat, lng, accuracy, speed, timestamp) {
      // 组装成AMap兼容格式，直接走_onLocation处理管道
      final locData = <String, Object>{
        'latitude': lat,
        'longitude': lng,
        'accuracy': accuracy,
        'speed': speed,
        'timestamp': timestamp,
        'errorCode': 0,
        'locationType': 1,
      };
      _onLocation(locData);
    };

    // 4. 初始化文件缓存上传器（必须在原生服务启动之前，避免init竞态）
    try {
      await LocationUploader().init();
      LocationUploader().setUserId(AuthService().userId ?? '');
      LocationUploader().setToken(AuthService().token ?? '');
    } catch (_) {}

    // 5. 启动原生ForegroundService（含AMapLocationClient + WakeLock）
    await startBackgroundLocationService();
    _lastGpsTime = DateTime.now();

    // 6. 启动上传定时器
    _scheduleUploadTimer();

    // 6. 定期检查运动状态
    _motionCheckTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkMotionState(),
    );

    // 7. GPS看门狗
    _gpsWatchdog = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkGpsHealth(),
    );

    // 8. 隧道URL轮询（每15分钟检查一次）
    _tunnelRefreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refreshTunnelUrl(),
    );
    // 启动时立即刷新一次
    _refreshTunnelUrl();

    _isRunning = true;
    debugPrint('[AmapLoc] 定位追踪已启动');
    return true;
  }

  /// 停止定位追踪
  void stopTracking() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _motionCheckTimer?.cancel();
    _motionCheckTimer = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _tunnelRefreshTimer?.cancel();
    _tunnelRefreshTimer = null;
    _positionBuffer.clear();
    _motion.stop();
    _recentLocations.clear();
    _isRunning = false;
    _currentLocation = null;
    _gpsLost = false;
    _lastGpsTime = null;

    stopBackgroundLocationService();
    debugPrint('[AmapLoc] 定位追踪已停止');
  }

  // ============================================================
  //  高德定位数据处理
  // ============================================================

  void _onLocation(Map<String, Object> locationData) {
    try {
      _totalPositions++;
      _lastGpsTime = DateTime.now();

      // 检查错误码
      final errorCode = locationData['errorCode'];
      if (errorCode != null && errorCode != 0) {
        final errorInfo = locationData['errorInfo'];
        debugPrint('[AmapLoc] 定位错误: $errorCode - $errorInfo');
        // 安全转换（原生可能返回 int/double/String）
        final eCode = (errorCode as num?)?.toInt() ?? -1;
        final eInfo = errorInfo?.toString();
        final msg = _amapErrorToMessage(eCode, eInfo);
        onError?.call(msg);
        return;
      }

      final lat = (locationData['latitude'] as num?)?.toDouble();
      final lng = (locationData['longitude'] as num?)?.toDouble();
      final accuracy = (locationData['accuracy'] as num?)?.toDouble() ?? 999;

      if (lat == null || lng == null) {
        _onGpsLoss();
        return;
      }

      // 精度校验
      // 更新最佳精度
      if (accuracy < _bestAccuracy) {
        _bestAccuracy = accuracy;
      }

      if (accuracy > AppConfig.maxAcceptableAccuracy) {
        _rejectedPositions++;
        _onGpsLoss();
        return;
      }

      // GPS恢复
      if (_gpsLost) {
        _gpsLost = false;
        debugPrint('[AmapLoc] GPS重新锁定');
      }
      _currentLocation = locationData;

      // ─── 3点滑动中值滤波 ───
      _recentLocations.add(locationData);
      if (_recentLocations.length > 3) _recentLocations.removeAt(0);

      if (_recentLocations.length == 3) {
        final p2 = _recentLocations[1];
        if (!p2.containsKey('latitude') || !p2.containsKey('longitude')) {
          _recentLocations.removeAt(1);
          _rejectedPositions++;
          return;
        }
        if (_isDriftPoint(_recentLocations[0], p2, _recentLocations[2])) {
          final speed = (locationData['speed'] as num?)?.toDouble() ?? 0;
          final disp = _motion.calculateDisplacement(lat, lng);
          final bool isReal =
              _motion.hasAccelActivity || disp > AppConfig.cumulativeMoveThreshold;
          if (speed < 0.5 && !isReal) {
            _removeFromBuffer(
              (p2['latitude'] as num).toDouble(),
              (p2['longitude'] as num).toDouble(),
            );
            _recentLocations.removeAt(1);
            _rejectedPositions++;
          }
        }
      }

      // 加入缓冲区
      _addToBuffer(lat, lng, accuracy, locationData);

      // 更新运动状态
      _updateMotionState(lat, lng, locationData);

      // 对外回调
      onLocationChanged?.call(lat, lng, accuracy,
          (locationData['speed'] as num?)?.toDouble());
    } catch (e) {
      debugPrint('[AmapLoc] 定位数据处理异常: $e');
    }
  }

  void _onGpsLoss() {
    if (!_gpsLost) {
      _gpsLost = true;
      if (_currentLocation != null) {
        onError?.call('GPS信号弱，定位精度低');
      }
    }
  }

  bool _isDriftPoint(
      Map<String, Object> p1, Map<String, Object> p2, Map<String, Object> p3) {
    final d12 = _haversineKm(
      (p1['latitude'] as num).toDouble(),
      (p1['longitude'] as num).toDouble(),
      (p2['latitude'] as num).toDouble(),
      (p2['longitude'] as num).toDouble(),
    );
    final d23 = _haversineKm(
      (p2['latitude'] as num).toDouble(),
      (p2['longitude'] as num).toDouble(),
      (p3['latitude'] as num).toDouble(),
      (p3['longitude'] as num).toDouble(),
    );
    final d13 = _haversineKm(
      (p1['latitude'] as num).toDouble(),
      (p1['longitude'] as num).toDouble(),
      (p3['latitude'] as num).toDouble(),
      (p3['longitude'] as num).toDouble(),
    );
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

  void _updateMotionState(
      double lat, double lng, Map<String, Object> locationData) {
    final displacement = _motion.calculateDisplacement(lat, lng);
    _motion.updateState(
      speed: (locationData['speed'] as num?)?.toDouble(),
      gpsLost: false,
      cumulativeDisplacement: displacement,
      currentLat: lat,
      currentLng: lng,
    );
  }

  void _checkMotionState() {
    if (!_isRunning) return;
    if (_currentLocation == null) return;
    final lat = (_currentLocation!['latitude'] as num).toDouble();
    final lng = (_currentLocation!['longitude'] as num).toDouble();
    final displacement = _motion.calculateDisplacement(lat, lng);
    _motion.updateState(
      speed: (_currentLocation!['speed'] as num?)?.toDouble(),
      gpsLost: _gpsLost,
      cumulativeDisplacement: displacement,
      currentLat: lat,
      currentLng: lng,
    );
  }

  void _checkGpsHealth() async {
    if (!_isRunning) return;
    if (_lastGpsTime == null) return;
    final elapsed = DateTime.now().difference(_lastGpsTime!);
    if (elapsed.inSeconds < 60) return;

    // 限频保护：每小时最多重建3次，超限则降级等待
    final now = DateTime.now();
    if (_gpsRestartResetTime == null || now.difference(_gpsRestartResetTime!) > _gpsRestartWindow) {
      _gpsRestartCount = 0;
      _gpsRestartResetTime = now;
    }
    if (_gpsRestartCount >= _maxGpsRestarts) {
      debugPrint('[AmapLoc] GPS重启已达上限($_maxGpsRestarts次/小时)，降级等待用户手动恢复');
      onError?.call('GPS定位不稳定，请稍后手动重启APP');
      return;
    }
    _gpsRestartCount++;

    debugPrint('[AmapLoc] GPS流已静默${elapsed.inSeconds}秒，正在重建ForegroundService... (第$_gpsRestartCount次)');
    onError?.call('GPS流超时，正在重启定位服务...');

    // 重建原生ForegroundService（内含AMapLocationClient重启）
    stopBackgroundLocationService();
    // 等旧实例销毁完成再启动，防止竞态
    await Future.delayed(_gpsRestartDelay);
    await startBackgroundLocationService();
    _lastGpsTime = DateTime.now();
  }

  /// 轮询服务器获取最新隧道URL，有变更则自动替换
  void _refreshTunnelUrl() {
    AppConfig.refreshTunnelUrl();
  }

  // ============================================================
  //  缓存 & 上报
  // ============================================================

  void _addToBuffer(
      double lat, double lng, double accuracy, Map<String, Object> locationData) {
    // 解析时间戳 (高德返回可能是ISO 8601字符串或numeric epoch毫秒数)
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    final timeStr = locationData['locationTime'] as String? ??
        locationData['callbackTime'] as String?;
    if (timeStr != null && timeStr.isNotEmpty) {
      try {
        if (RegExp(r'^\d+$').hasMatch(timeStr)) {
          timestamp = int.parse(timeStr);
        } else {
          timestamp = DateTime.parse(timeStr).millisecondsSinceEpoch;
        }
      } catch (_) {}
    }

    _positionBuffer.add(_PositionRecord(
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      speed: (locationData['speed'] as num?)?.toDouble(),
      timestamp: timestamp,
    ));

    // 同时写入文件缓存（用于离线恢复，APP重启不丢）
    try {
      final uid = AuthService().userId ?? '';
      LocationUploader().enqueue(LocationPoint(
        userId: uid,
        latitude: lat,
        longitude: lng,
        accuracy: accuracy,
        speed: (locationData['speed'] as num?)?.toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      ));
    } catch (_) {
      // 不影响定位主流程
    }
    if (_positionBuffer.length >= _currentBufferSize) {
      _flushBuffer();
    }
  }

  bool _isFlushing = false;

  Future<void> _flushBuffer() async {
    if (_positionBuffer.isEmpty || _isFlushing) return;
    _isFlushing = true;
    try {
      final batch = _positionBuffer.toList();
      assert(batch.isNotEmpty, '_flushBuffer called with empty buffer');
      final last = batch.last;

      bool success = false;

      try {
        // 批量上传：每个点保持独立坐标和时间戳，不平均
        if (batch.length == 1) {
          await _api.post(AppConfig.apiReportLocation, data: {
            'lng': last.lng,
            'lat': last.lat,
            'accuracy': last.accuracy,
            'speed': last.speed ?? 0,
            'timestamp': last.timestamp,
            'batch_size': 1,
          });
        } else {
          // 批量端点：一次上传所有点，每个点独立
          await _api.post('/api/v1/location/batch', data: {
            'points': batch.map((p) => {
              'lng': p.lng,
              'lat': p.lat,
              'accuracy': p.accuracy,
              'speed': p.speed ?? 0,
              'timestamp': p.timestamp,
            }).toList(),
          });
        }
        success = true;
      } catch (e) {
        debugPrint('[AmapLoc] 上传定位失败(batch=${batch.length}): $e');
      }

      if (success) {
        // 只移除已上传的快照条目（保留 await 期间新加的点）
        // _positionBuffer是Queue，用removeWhere按引用相等移除
        final batchSet = batch.toSet();
        _positionBuffer.removeWhere((p) => batchSet.contains(p));

        // 围栏检测（非关键）
        if (!_gpsLost) {
          try {
            await _api.post('/api/v1/fences/auto-check', data: {
              'lat': currentLat ?? last.lat,
              'lng': currentLng ?? last.lng,
              'accuracy': currentAccuracy,
            });
          } catch (e) {
            debugPrint('[AmapLoc] 围栏检测请求失败: $e');
          }
        }
      } else {
        debugPrint('[AmapLoc] 保留${batch.length}个点在缓冲区重试');
      }
    } finally {
      _isFlushing = false;
    }
  }

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
  /// 高德定位错误码 → 中文提示
  /// 错误码参考: https://lbs.amap.com/api/android-location-sdk/guide/utilities/errorcode
  String _amapErrorToMessage(int code, String? info) {
    switch (code) {
      case 1: return '定位失败：关键参数缺失（请检查高德Key配置）';
      case 2: return '定位失败：网络连接异常，请检查网络';
      case 3: return '定位失败：读取本地配置信息异常（请检查高德Key配置）';
      case 4: return '定位失败：协议解析失败（请检查高德Key是否正确）';
      case 5: return '定位失败：获取基站/WiFi信息失败，请检查GPS和网络';
      case 6: return '定位失败：定位结果缓存异常';
      case 7: return '定位失败：Key鉴权失败，请检查高德Key配置';
      case 8: return '定位失败：初始化异常';
      case 9: return '定位失败：定位服务未启动';
      case 10: return '定位失败：定位芯片错误，请检查GPS是否开启';
      case 11: return '定位失败：缺少定位权限，请在设置中开启';
      case 12: return '定位失败：缺少网络权限';
      case 13: return '定位失败：WLAN辅助定位失败';
      case 14: return '定位失败：GPS定位失败，请到开阔地带重试';
      case 21: return '定位失败：地理位置定位失败，请检查定位开关';
      default: return '定位失败（$code）: ${info ?? "未知错误"}';
    }
  }
}

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

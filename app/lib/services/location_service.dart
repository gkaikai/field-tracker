import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import 'api_service.dart';

/// 定位服务
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _uploadTimer;
  int _currentInterval = AppConfig.locationIntervalSeconds;
  bool _isRunning = false;

  // 回调
  void Function(Position position)? onLocationChanged;
  void Function(String error)? onError;

  LocationService._internal();

  Position? get currentPosition => _currentPosition;
  bool get isRunning => _isRunning;

  /// 启动持续定位
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    // 检查定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      onError?.call('定位权限被拒绝');
      return false;
    }

    // 获取当前位置
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      onError?.call('获取位置失败: $e');
    }

    // 持续监听位置变化（距离5米变化即触发）
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        _currentPosition = position;
        onLocationChanged?.call(position);
      },
      onError: (error) {
        onError?.call('定位流错误: $error');
      },
    );

    // 定时上报位置
    _uploadTimer = Timer.periodic(
      Duration(seconds: _currentInterval),
      (_) => _uploadPosition(),
    );

    _isRunning = true;
    return true;
  }

  /// 停止定位
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _isRunning = false;
  }

  /// 上报位置到服务器，并根据速度自适应调整频率（省电模式）
  Future<void> _uploadPosition() async {
    if (_currentPosition == null) return;

    try {
      await _api.post(AppConfig.apiReportLocation, data: {
        'lng': _currentPosition!.longitude,
        'lat': _currentPosition!.latitude,
        'accuracy': _currentPosition!.accuracy,
        'speed': _currentPosition!.speed,
        'timestamp': _currentPosition!.timestamp.millisecondsSinceEpoch,
      });

      // 省电模式：根据速度调整上报频率
      if (AppConfig.powerSaveStationaryInterval > 0) {
        final speed = _currentPosition!.speed; // m/s
        final isMoving = speed > AppConfig.powerSaveSpeedThreshold / 3.6;
        final newInterval = isMoving
            ? AppConfig.powerSaveMovingInterval
            : AppConfig.powerSaveStationaryInterval;

        if (_uploadTimer != null && _currentInterval != newInterval) {
          _uploadTimer?.cancel();
          _currentInterval = newInterval;
          _uploadTimer = Timer.periodic(
            Duration(seconds: newInterval),
            (_) => _uploadPosition(),
          );
        }
      }
    } catch (e) {
      // 网络失败静默处理（下次重试）
    }

    // 上报成功后自动检测围栏进出
    try {
      await _api.post('/api/v1/fences/auto-check', data: {
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
      });
    } catch (_) {
      // 围栏检测失败不阻塞定位
    }
  }
}

/// 后台定位保活 - 鸿蒙兼容占位
void startBackgroundService() {
  // 已禁用：flutter_background_service 不兼容鸿蒙
}

/// WorkManager后台周期性任务
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'periodicLocationUpload') {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return false;
      try {
        final position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          final api = ApiService();
          api.setToken(token);
          await api.post(AppConfig.apiReportLocation, data: {
            'lng': position.longitude,
            'lat': position.latitude,
          });
        }
      } catch (_) {}
      return true;
    }
    return false;
  });
}

/// 注册WorkManager周期性定位任务
void registerPeriodicLocationTask() {
  Workmanager().registerPeriodicTask(
    'periodicLocationUpload',
    'periodicLocationUpload',
    frequency: Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: Duration(minutes: 1),
  );
}

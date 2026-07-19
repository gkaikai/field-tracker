import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import 'api_service.dart';

/// 定位服务 — 使用 Geolocator（兼容HarmonyOS）+ 高精度GPS
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
  void Function(double lat, double lng, double accuracy)? onLocationChanged;
  void Function(String error)? onError;

  LocationService._internal();

  double? get currentLat => _currentPosition?.latitude;
  double? get currentLng => _currentPosition?.longitude;
  bool get isRunning => _isRunning;

  /// 启动持续定位
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

    // 3. 获取一次高精度GPS位置（确保第一次定位就有数据）
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation, // 导航级精度
      );
    } catch (e) {
      // 首次定位失败不阻止继续
    }

    // 4. 持续监听位置变化（精度最高，距离过滤0米）
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, // 导航级精度
        distanceFilter: 0,       // 每一米都触发更新
        timeLimit: null,
      ),
    ).listen(
      (Position position) {
        _currentPosition = position;
        onLocationChanged?.call(
          position.latitude,
          position.longitude,
          position.accuracy,
        );
      },
      onError: (error) {
        onError?.call('定位流错误: $error');
      },
    );

    // 5. 定时上报位置
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
    _currentPosition = null;
  }

  /// 上报位置到服务器
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
    } catch (e) {
      // 网络失败静默处理
    }

    // 围栏检测
    try {
      await _api.post('/api/v1/fences/auto-check', data: {
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
      });
    } catch (_) {}
  }

  /// 获取最新一次位置（供单次调用场景用）
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

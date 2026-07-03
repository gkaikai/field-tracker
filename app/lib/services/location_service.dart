import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
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

    // 持续监听位置变化
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
      Duration(seconds: AppConfig.locationIntervalSeconds),
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
      // 网络失败静默处理（下次重试）
    }
  }
}

/// 后台定位保活服务
/// 创建前台服务避免iOS/Android系统杀死定位进程
void startBackgroundService() {
  final service = FlutterBackgroundService();

  service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: (service) {
        service.invoke('startService', {'action': 'started'});
      },
      onBackground: (service) async {
        WidgetsFlutterBinding.ensureInitialized();
        return true;
      },
    ),
    androidConfiguration: AndroidConfiguration(
      autoStart: false,
      isForegroundMode: true,
      autoStartOnBoot: false,
      notificationChannelId: AppConfig.notificationChannelId,
      initialNotificationTitle: '外勤定位',
      initialNotificationContent: '正在后台追踪位置...',
      foregroundServiceNotificationId: 888,
      onStart: (service) {
        (service as AndroidServiceInstance).setForegroundNotificationInfo(
          title: '外勤定位',
          content: '正在后台追踪位置...',
        );

        service.on('startService').listen((event) {
          service.invoke('startService', {'action': 'started'});
        });

        service.on('stopService').listen((event) {
          service.invoke('stopService', {'action': 'stopped'});
        });
      },
    ),
  );

  service.startService();
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
            'accuracy': position.accuracy,
            'speed': position.speed,
            'timestamp': position.timestamp.millisecondsSinceEpoch,
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
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: Duration(minutes: 1),
  );
}

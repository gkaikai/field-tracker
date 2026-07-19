import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'package:amap_flutter_location/amap_location_option.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import '../config/amap_key.dart';
import 'api_service.dart';

/// 定位服务 — 使用高德定位SDK（取代Geolocator）
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  AMapFlutterLocation? _locationPlugin;
  double? _currentLat;
  double? _currentLng;
  double? _currentAccuracy;
  int? _currentLocationType;
  StreamSubscription<Map<String, Object>>? _locationSubscription;
  Timer? _uploadTimer;
  int _currentInterval = AppConfig.locationIntervalSeconds;
  bool _isRunning = false;

  // 回调
  void Function(double lat, double lng, double accuracy)? onLocationChanged;
  void Function(String error)? onError;

  LocationService._internal();

  double? get currentLat => _currentLat;
  double? get currentLng => _currentLng;
  bool get isRunning => _isRunning;

  /// 初始化高德定位SDK（在APP启动时调用一次）
  static void initSdk() {
    // 设置隐私合规（必须在startLocation之前调用）
    AMapFlutterLocation.updatePrivacyShow(true, true);
    AMapFlutterLocation.updatePrivacyAgree(true);
    // 设置API Key
    AMapFlutterLocation.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey);
  }

  /// 启动持续定位
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    try {
      _locationPlugin = AMapFlutterLocation();

      // 设置定位参数：高精度、GPS优先、2秒更新
      final option = AMapLocationOption(
        locationInterval: 2000,         // 2秒更新一次位置
        locationMode: AMapLocationMode.Hight_Accuracy,
        needAddress: false,             // 轨迹不需要地址信息，省电
        onceLocation: false,
        desiredAccuracy: DesiredAccuracy.Best,
      );
      _locationPlugin!.setLocationOption(option);

      // 监听定位结果
      _locationSubscription = _locationPlugin!.onLocationChanged().listen(
        (Map<String, Object> result) {
          final lat = result['latitude'] as double?;
          final lng = result['longitude'] as double?;
          final accuracy = result['accuracy'] as double?;
          final locType = result['locationType'] as int?;

          if (lat != null && lng != null && lat != 0 && lng != 0) {
            _currentLat = lat;
            _currentLng = lng;
            _currentAccuracy = accuracy;
            _currentLocationType = locType;

            // 定位类型：1=GPS，其他=网络/基站
            onLocationChanged?.call(lat, lng, accuracy ?? 0);
          }
        },
        onError: (error) {
          onError?.call('高德定位出错: $error');
        },
      );

      // 开始定位
      _locationPlugin!.startLocation();

      // 定时上报位置到服务器
      _uploadTimer = Timer.periodic(
        Duration(seconds: _currentInterval),
        (_) => _uploadPosition(),
      );

      _isRunning = true;
      return true;
    } catch (e) {
      onError?.call('定位启动失败: $e');
      return false;
    }
  }

  /// 停止定位
  void stopTracking() {
    _locationPlugin?.stopLocation();
    _locationPlugin?.destroy();
    _locationPlugin = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _isRunning = false;
  }

  /// 上报位置到服务器，并根据速度自适应调整频率（省电模式）
  Future<void> _uploadPosition() async {
    if (_currentLat == null || _currentLng == null) return;

    try {
      await _api.post(AppConfig.apiReportLocation, data: {
        'lng': _currentLng,
        'lat': _currentLat,
        'accuracy': _currentAccuracy ?? 0,
        'location_type': _currentLocationType ?? 0,  // 1=GPS, 其他=网络
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 省电模式：根据定位类型调整上报频率
      // GPS定位(locationType=1)时频率可以低一些，网络定位精度差需要更频繁更新
      if (AppConfig.powerSaveStationaryInterval > 0) {
        final isGps = _currentLocationType == 1;
        final newInterval = isGps
            ? AppConfig.powerSaveMovingInterval     // GPS模式上报间隔
            : AppConfig.powerSaveStationaryInterval; // 网络模式更频繁

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
        'lat': _currentLat,
        'lng': _currentLng,
      });
    } catch (_) {}
  }
}

/// WorkManager后台周期性任务（备选，使用高德定位SDK有HarmonyOS兼容问题）
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'periodicLocationUpload') {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return false;
      try {
        final api = ApiService();
        api.setToken(token);
        // WorkManager中用高德定位SDK也行，但兼容性不确定
        // 先用Geolocator作为WorkManager的后备
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

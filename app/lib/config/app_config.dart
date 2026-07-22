import 'env_config.dart';

/// APP全局配置
class AppConfig {
  /// 后端API地址 - 初始化后静态使用
  static late String baseUrl;

  /// WebSocket地址 - 基于 baseUrl 自动构建
  static String get wsUrl => '${baseUrl.replaceFirst('http', 'ws')}/ws/location';

  /// 初始化 baseUrl（在 main 或 splash 页调用）
  static Future<void> init() async {
    baseUrl = await EnvConfig.baseUrl;
  }
  
  /// 动态修改服务器地址（用户手动设置）
  static Future<void> setServerUrl(String url) async {
    await EnvConfig.setBaseUrl(url);
    baseUrl = url;
  }
  
  // 高德地图Key（iOS用Bundle ID绑定，Android用PackageName+SHA1绑定）
  static const String amapApiKey = '0e00439a3a2b04282e78083ea7a9b19d';

  // ============================================================
  //  定位采集参数
  // ============================================================

  /// 移动中上传间隔（秒）
  static const int movingUploadInterval = 12;

  /// 不确定期上传间隔（秒）
  static const int uncertainUploadInterval = 30;

  /// 静止期上传间隔（秒）
  static const int stationaryUploadInterval = 300; // 5分钟

  /// 移动判定 — GPS速度阈值（m/s）
  static const double movingSpeedThreshold = 1.0;  // ≈3.6km/h

  /// 静止判定 — GPS速度阈值（m/s）
  static const double stationarySpeedThreshold = 0.5;

  /// 精度过滤 — 超过此值丢弃（米）
  static const double maxAcceptableAccuracy = 100.0;

  /// 漂移滤波 — 孤立点距离前后点阈值（km）
  static const double driftMaxDistKm = 1.5;
  static const double driftSkipDistKm = 2.5;

  /// 累计位移 — 超过此值判定为移动（米）
  static const double cumulativeMoveThreshold = 50.0;

  /// 累计位移 — 低于此值判定为静止（米）
  static const double cumulativeStillThreshold = 20.0;

  /// UNCERTAIN 进入 STATIONARY 的等待时间（秒）
  static const int uncertainToStationarySec = 60;

  /// UNCERTAIN 触发前的最低持续秒数
  static const int uncertainTriggerSec = 15;

  /// MOVING切入UNCERTAIN后再恢复MOVING的加速度振动持续时间（秒）
  static const int accelerometerVibrationSec = 10;

  // ============================================================
  //  加速度传感器参数
  // ============================================================

  /// 加速度采样间隔（毫秒）
  static const int accelerometerSampleIntervalMs = 500; // 0.5秒

  /// 加速度方差 - 静止阈值
  static const double accelStillThreshold = 1.5;

  /// 加速度方差 - 行走阈值（正常步行净加速度波动≈2-5 m/s²）
  static const double accelWalkThreshold = 3.5;

  /// 连续几次采样判定稳定结果
  static const int accelConsecutiveSamples = 3;

  // ============================================================
  //  后台定位 & 通知
  // ============================================================

  // 后台定位保活 - 通知渠道
  static const String notificationChannelId = 'field_tracker_location';
  static const String notificationChannelName = '定位服务';
  static const String notificationChannelDesc = '后台定位追踪通知';

  // API路径
  static const String apiLogin = '/api/v1/auth/login';
  static const String apiReportLocation = '/api/v1/location/report';
  static const String apiCurrentLocation = '/api/v1/location/current';
  static const String apiBatchLocation = '/api/v1/location/batch';
  static const String apiTrack = '/api/v1/track';
  static const String apiCheckin = '/api/v1/attendance/checkin';
  static const String apiAttendanceRecords = '/api/v1/attendance/records';
}

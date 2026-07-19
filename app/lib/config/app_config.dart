import 'env_config.dart';

/// APP全局配置
class AppConfig {
  /// 后端API地址 - 根据环境自动选择
  /// 开发模式: http://localhost:3000
  /// 生产模式: https://bf521a2cb506283e-...serveousercontent.com
  static String get baseUrl => EnvConfig.baseUrl;
  
  // 高德地图Key（iOS用Bundle ID绑定，Android用PackageName+SHA1绑定）
  static const String amapApiKey = '0e00439a3a2b04282e78083ea7a9b19d';
  
  // 定位上报间隔（秒）
  static const int locationIntervalSeconds = 60;
  
  // 省电模式：静止时降低频率（秒），0=禁用省电
  static const int powerSaveStationaryInterval = 60; // 静止时每1分钟（原来300秒太久了）
  static const int powerSaveMovingInterval = 30;     // 运动时每30秒（更密集）
  static const double powerSaveSpeedThreshold = 0.5; // 运动判定阈值 km/h
  
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

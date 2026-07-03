/// APP全局配置
class AppConfig {
  // 后端API地址
  static const String baseUrl = 'http://localhost:3000';
  
  // 高德地图Key（iOS用Bundle ID绑定，Android用PackageName+SHA1绑定）
  static const String amapApiKey = '0e00439a3a2b04282e78083ea7a9b19d';
  
  // 定位上报间隔（秒）
  static const int locationIntervalSeconds = 10;
  
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

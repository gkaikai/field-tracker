/// 高德地图 & 定位 SDK 配置
class AMapConfig {
  /// 高德地图 API Key
  /// Android: 配置在 AndroidManifest.xml 中
  /// iOS:     配置在 Info.plist 中
  /// 以下 Dart 层配置供 AMapWidget 初始化使用
  static const String androidKey = '0e00439a3a2b04282e78083ea7a9b19d';
  static const String iosKey = '9debae73ed4f59ce9f934c9b1fda1a23';

  /// 高德 Web Service API Key（地理编码/搜索用）
  static const String webServiceKey = 'f54f44a83e49995348e72713f2ca1b9a';
  static const String webServiceSecurityCode = '7ac68442bb2d4a49a4aab6237ea29f48';

  /// WebSocket/HTTP 后端地址
  /// - 模拟器/电脑端: http://localhost:3000
  /// - 真机同一WiFi:   http://<电脑IP>:3000
  /// - 生产服务器:      https://your-domain.com
  static const String serverBaseUrl = 'https://f8325e03e04d6c3b-123-123-97-213.serveousercontent.com';
  static const String wsUrl = 'wss://f8325e03e04d6c3b-123-123-97-213.serveousercontent.com/ws/location';

  /// 定位上报参数
  static const int uploadBatchSize = 10;
  static const int uploadIntervalMs = 60000;
}

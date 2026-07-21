/// 高德地图 & 定位 SDK 配置
class AMapConfig {
  /// 高德地图 API Key
  /// Android: 配置在 AndroidManifest.xml 中
  /// iOS:     配置在 Info.plist 中
  /// 以下 Dart 层配置供 AMapWidget 初始化使用
  static const String androidKey = '0e00439a3a2b04282e78083ea7a9b19d';
  static const String iosKey = '9debae73ed4f59ce9f934c9b1fda1a23';

  /// 高德 Web Service API Key（地理编码/搜索用）
  static const String webServiceKey = '665f6c9959c69f9c08ae1d869d2b7abd';
  static const String webServiceSecurityCode = '';

  /// 定位上报参数
  static const int uploadBatchSize = 10;
  static const int uploadIntervalMs = 60000;
}

/// 高德地图 & 定位 SDK 配置
///
/// 密钥通过编译时 --dart-define 注入，不再硬编码在源码中。
/// 构建命令示例:
///   flutter build apk --dart-define=AMAP_ANDROID_KEY=xxx --dart-define=AMAP_IOS_KEY=xxx --dart-define=AMAP_WS_KEY=xxx
///
/// 本地开发时可在 .env 文件中配置，由 flutter_dotenv 加载。
library;

class AMapConfig {
  /// 高德地图 API Key（通过 --dart-define 编译注入）
  /// Android Key
  static const String androidKey = String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');
  /// iOS Key
  static const String iosKey = String.fromEnvironment('AMAP_IOS_KEY', defaultValue: '');

  /// 高德 Web Service API Key（地理编码/搜索用）
  static const String webServiceKey = String.fromEnvironment('AMAP_WS_KEY', defaultValue: '');
  static const String webServiceSecurityCode = '';

  /// 定位上报参数
  static const int uploadBatchSize = 10;
  static const int uploadIntervalMs = 60000;

  /// 校验密钥是否已配置（开发模式下可跳过）
  static bool get isConfigured =>
      androidKey.isNotEmpty && webServiceKey.isNotEmpty;
}

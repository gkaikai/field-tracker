/// 环境配置 - 根据构建模式选择后端 API 地址
///
/// 开发模式 (flutter run / debug):        http://localhost:3000
/// 生产模式 (flutter build --release):     Serveo 公网地址
library;

import 'package:flutter/foundation.dart';

/// 根据当前构建模式获取环境配置
class EnvConfig {
  /// 后端 API 基础地址
  static String get baseUrl {
    if (kReleaseMode) {
      // 生产模式 - 通过 Serveo 公网隧道访问
      return 'https://bf521a2cb506283e-123-123-97-213.serveousercontent.com';
    } else if (kProfileMode) {
      // Profile 模式 - 也使用生产地址
      return 'https://bf521a2cb506283e-123-123-97-213.serveousercontent.com';
    } else {
      // 开发/调试模式 - 本地服务器
      // Android 模拟器用 10.0.2.2 映射宿主机 localhost
      // iOS 模拟器直接用 localhost
      return 'http://localhost:3000';
    }
  }

  /// 是否为生产环境
  static bool get isProduction => kReleaseMode;

  /// 是否为开发环境
  static bool get isDevelopment => !kReleaseMode;
}

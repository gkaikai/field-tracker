/// 环境配置 - 根据构建模式选择后端 API 地址
///
/// 开发模式 (flutter run / debug):        http://localhost:3000
/// 生产模式 (flutter build --release):     从 SharedPreferences 读取，用户可手动配置
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 根据当前构建模式获取环境配置
class EnvConfig {
  /// 默认生产地址（当用户未手动设置时使用）
  static const String _defaultProdUrl = 'https://39cf0a7f34115140-123-123-97-213.serveousercontent.com';

  /// 后端 API 基础地址
  static String _cachedBaseUrl = '';
  static Future<String> get baseUrl async {
    if (_cachedBaseUrl.isNotEmpty) return _cachedBaseUrl;

    if (kReleaseMode || kProfileMode) {
      final prefs = await SharedPreferences.getInstance();
      _cachedBaseUrl = prefs.getString('server_base_url') ?? _defaultProdUrl;
      return _cachedBaseUrl;
    } else {
      return 'http://localhost:3000';
    }
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_base_url', url);
    _cachedBaseUrl = url;
  }
}

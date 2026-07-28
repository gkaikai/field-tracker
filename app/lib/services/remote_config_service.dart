/// 远程服务器配置服务
///
/// 从 GitHub raw（永远可达）拉取最新的服务器地址列表，
/// 解决 serveo 隧道地址频繁变化后无需重装 APK 的问题。
library;

import 'dart:convert' show jsonDecode;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env_config.dart';

/// 单条服务器配置
class ServerEntry {
  final String url;
  final String label; // "primary", "fallback"
  final DateTime createdAt;

  ServerEntry({
    required this.url,
    required this.label,
    required this.createdAt,
  });

  factory ServerEntry.fromJson(Map<String, dynamic> json) {
    return ServerEntry(
      url: json['url'] as String,
      label: json['label'] as String? ?? 'unknown',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// 远程配置 JSON 结构
class RemoteServerConfig {
  final int version;
  final DateTime updatedAt;
  final List<ServerEntry> servers;

  RemoteServerConfig({
    required this.version,
    required this.updatedAt,
    required this.servers,
  });

  factory RemoteServerConfig.fromJson(Map<String, dynamic> json) {
    final serverList = (json['servers'] as List<dynamic>?)
            ?.map((e) => ServerEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return RemoteServerConfig(
      version: json['version'] as int? ?? 1,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      servers: serverList,
    );
  }
}

/// 服务器选择器 — 负责健康检查、切换、故障转移
class ServerSelector {
  /// 配置源 URL（唯一硬编码，写死在 APK 里）
  /// ⚠️ GitHub raw URL 依赖 github.com 可用性，若迁移至私有仓库或自建 CDN 需同步更新此地址
  /// 建议：后续改为可从云端动态下发的启动配置，消除此硬编码点
  static const String configUrl =
      'https://raw.githubusercontent.com/gkaikai/field-tracker-config/main/config.json';

  /// 健康检查超时（秒）
  static const int healthCheckTimeout = 8;

  /// 连续失败阈值 — 达到后触发切换
  static const int consecutiveFailureThreshold = 3;

  /// 熔断时间窗口（秒）— 在此窗口内的连续失败才计入
  static const int circuitBreakerWindowSec = 120;

  /// 后台刷新间隔（分钟）
  static const int backgroundRefreshMinutes = 60;

  /// 当前在用地址
  static String _currentUrl = '';

  /// 熔断状态
  static int _consecutiveFailures = 0;
  static int _lastFailureTimestampMs = 0;

  static String get currentUrl => _currentUrl;

  /// 从远程配置源获取最新的服务器列表
  static Future<RemoteServerConfig?> fetchRemoteConfig() async {
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse(configUrl))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final config = RemoteServerConfig.fromJson(
              jsonDecode(resp.body) as Map<String, dynamic>);
          debugPrint('[ServerSelector] 远程配置获取成功: '
              '${config.servers.length}个服务器');
          return config;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[ServerSelector] 获取远程配置失败: $e');
    }
    return null;
  }

  /// 测试单个URL是否可达（/health）
  static Future<bool> testHealth(String url) async {
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('$url/health'))
            .timeout(const Duration(seconds: healthCheckTimeout));
        return resp.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[ServerSelector] 健康检查失败: $url: $e');
      return false;
    }
  }

  /// 初始化 — 在 APP 启动时调用
  /// 返回最终可用的服务器URL，如果全部不通返回最后一个尝试的URL
  static Future<String> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 优先用本地保存的URL
    final savedUrl = prefs.getString('server_base_url') ?? '';
    if (savedUrl.isNotEmpty) {
      final ok = await testHealth(savedUrl);
      if (ok) {
        debugPrint('[ServerSelector] 本地保存的URL可用: $savedUrl');
        _currentUrl = savedUrl;
        return savedUrl;
      }
      debugPrint('[ServerSelector] 本地URL不通，尝试远程配置');
    }

    // 2. 从远程配置获取服务器列表
    final resolved = await _resolveFromRemote(prefs);
    if (resolved.isNotEmpty) return resolved;

    // 3. 全部不通，无硬编码兜底地址
    const fallbackUrl = '';
    debugPrint('[ServerSelector] 全部不通，无可用服务器');
    _currentUrl = fallbackUrl;
    return fallbackUrl;
  }

  /// 从远程配置解析可用服务器
  static Future<String> _resolveFromRemote(SharedPreferences prefs) async {
    final config = await fetchRemoteConfig();
    if (config == null || config.servers.isEmpty) {
      // 远程配置也拿不到，兜底走硬编码地址
      final fallback = await EnvConfig.baseUrl;
      if (fallback.isNotEmpty) {
        final ok = await testHealth(fallback);
        if (ok) {
          _currentUrl = fallback;
          await _saveUrl(prefs, fallback);
          return fallback;
        }
      }
      return '';
    }

    // 按 label 排序：primary 优先
    final sorted = List<ServerEntry>.from(config.servers);
    sorted.sort((a, b) {
      final aScore = a.label == 'primary' ? 0 : 1;
      final bScore = b.label == 'primary' ? 0 : 1;
      return aScore.compareTo(bScore);
    });

    for (final server in sorted) {
      final ok = await testHealth(server.url);
      if (ok) {
        debugPrint('[ServerSelector] 使用服务器: '
            '${server.label} ${server.url}');
        _currentUrl = server.url;
        await _saveUrl(prefs, server.url);
        // 保存所有备用URL
        _saveBackupUrls(prefs, config);
        return server.url;
      }
    }

    return '';
  }

  /// 请求失败时调用 — 触发熔断/切换
  static Future<String?> onRequestFailed() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 如果距上次失败超过窗口期，重置计数
    if (now - _lastFailureTimestampMs > circuitBreakerWindowSec * 1000) {
      _consecutiveFailures = 0;
    }

    _consecutiveFailures++;
    _lastFailureTimestampMs = now;
    if (_consecutiveFailures < consecutiveFailureThreshold) {
      // 还没到阈值，不切换
      return null;
    }

    // 达到阈值，重置计数并切换
    _consecutiveFailures = 0;
    debugPrint('[ServerSelector] 连续$consecutiveFailureThreshold次失败，切换服务器');

    final prefs = await SharedPreferences.getInstance();

    // 先试本地保存的备用URL
    final backupUrls = prefs.getStringList('backup_urls') ?? [];
    for (final url in backupUrls) {
      if (url == _currentUrl) continue;
      final ok = await testHealth(url);
      if (ok) {
        debugPrint('[ServerSelector] 切换到备用: $url');
        _currentUrl = url;
        await _saveUrl(prefs, url);
        return url;
      }
    }

    // 备用全不通，重新拉取远程配置
    final newUrl = await _resolveFromRemote(prefs);
    if (newUrl.isNotEmpty) {
      return newUrl;
    }

    return null; // 全挂了
  }

  /// 请求成功时 — 重置连续失败计数
  static void onRequestSuccess() {
    _consecutiveFailures = 0;
  }

  /// 保存当前URL到 SharedPreferences
  static Future<void> _saveUrl(SharedPreferences prefs, String url) async {
    await EnvConfig.setBaseUrl(url);
  }

  /// 保存所有远程配置中的URL为备用列表
  static Future<void> _saveBackupUrls(
      SharedPreferences prefs, RemoteServerConfig config) async {
    final urls = config.servers
        .where((s) => s.url != _currentUrl)
        .map((s) => s.url)
        .toList();
    if (urls.isNotEmpty) {
      await prefs.setStringList('backup_urls', urls);
    }
  }

  /// 后台定时刷新远程配置
  static Future<void> backgroundRefresh() async {
    debugPrint('[ServerSelector] 后台刷新远程配置...');
    final config = await fetchRemoteConfig();
    if (config == null) return;

    final prefs = await SharedPreferences.getInstance();
    await _saveBackupUrls(prefs, config);

    // 如果当前URL在配置中还是 primary，且还有效，什么都不做
    final currentInConfig = config.servers.any((s) => s.url == _currentUrl);
    if (currentInConfig) {
      final ok = await testHealth(_currentUrl);
      if (ok) {
        debugPrint('[ServerSelector] 当前URL仍有效，无需切换');
        return;
      }
    }

    // 当前URL不在配置中或已失效 → 尝试切换
    debugPrint('[ServerSelector] 当前URL失效，尝试切换到最新配置');
    await _resolveFromRemote(prefs);
  }
}

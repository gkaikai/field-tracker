import 'env_config.dart';
import 'dart:convert' show jsonDecode;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP全局配置
class AppConfig {
  /// 后端API地址 - 初始化后静态使用
  static late String baseUrl;

  /// 备用服务器地址（隧道失效时自动切换）
  static String? backupUrl;

  /// WebSocket地址 - 基于 baseUrl 自动构建
  static String get wsUrl => '${baseUrl.replaceFirst('http', 'ws')}/ws/location';

  /// 初始化 baseUrl（在 main 或 splash 页调用）
  static Future<void> init() async {
    baseUrl = await EnvConfig.baseUrl;
    // 恢复备用隧道URL
    final prefs = await SharedPreferences.getInstance();
    final savedBackup = prefs.getString('backup_tunnel_url');
    if (savedBackup != null && savedBackup.isNotEmpty) {
      backupUrl = savedBackup;
    }
  }
  
  /// 动态修改服务器地址（用户手动设置）
  static Future<void> setServerUrl(String url) async {
    await EnvConfig.setBaseUrl(url);
    baseUrl = url;
  }

  /// 从服务器隧道API获取最新隧道URL并自动替换
  static Future<void> refreshTunnelUrl() async {
    try {
      final currentBase = baseUrl;
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('$currentBase/api/v1/tunnel'))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final newUrl = data['url'] as String?;
          final newBackupUrl = data['backup_url'] as String?;

          // 更新备用隧道
          if (newBackupUrl != null && newBackupUrl.isNotEmpty) {
            backupUrl = newBackupUrl;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('backup_tunnel_url', newBackupUrl);
            debugPrint('[AppConfig] 备用隧道URL已更新: $newBackupUrl');
          }

          if (newUrl != null && newUrl.isNotEmpty && newUrl != currentBase) {
            debugPrint('[AppConfig] 隧道URL已变更: $newUrl (原: $currentBase)');
            baseUrl = newUrl;
            await EnvConfig.setBaseUrl(newUrl);
            // 通知ForegroundService更新隧道URL
            await _passServerConfigToNative();
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[AppConfig] 隧道刷新失败，尝试备用隧道...');
      // 主URL不通 → 尝试切换备用
      await _trySwitchToBackup();
    }
  }

  /// 主URL不通时尝试切换到备用隧道
  static Future<void> _trySwitchToBackup() async {
    if (backupUrl == null || backupUrl!.isEmpty) return;
    if (backupUrl == baseUrl) return;

    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('$backupUrl/api/v1/tunnel/health'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          debugPrint('[AppConfig] 备用隧道可用，切换中: $backupUrl');
          baseUrl = backupUrl!;
          await EnvConfig.setBaseUrl(backupUrl!);
          await _passServerConfigToNative();
          debugPrint('[AppConfig] 已切换到备用隧道: $backupUrl');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[AppConfig] 备用隧道也不通: $e');
    }
  }

  /// 将最新服务器配置下发到原生ForegroundService
  /// 注：原生HTTP上传已关闭，此方法保留供恢复时使用
  static Future<void> _passServerConfigToNative() async {
    try {
      const channel = MethodChannel('com.fieldtracker/location_service');
      final auth = AuthService();
      await channel.invokeMethod('setServerConfig', {
        'url': baseUrl,
        'token': auth.token ?? '',
      });
      debugPrint('[AppConfig] 隧道URL已下发到原生层');
    } catch (e) {
      debugPrint('[AppConfig] 原生下发失败: $e');
    }
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

  /// 静止期GPS采集间隔（毫秒） — 省电优化
  static const int stationaryGpsIntervalMs = 60000;  // 60秒

  /// 移动期GPS采集间隔（毫秒）
  static const int movingGpsIntervalMs = 3000;  // 3秒

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

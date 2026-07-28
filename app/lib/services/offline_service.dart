import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

/// 离线模式服务 - 本地缓存定位数据，网络恢复后自动同步
class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  final _auth = AuthService();
  static const _cacheKey = 'offline_location_cache';
  static const _pendingCheckinKey = 'offline_checkin_cache';

  /// 安全解码 JSON 字符串为 List<Map>，数据损坏时返回空列表
  List<Map<String, dynamic>> _safeDecodeList(String? jsonStr) {
    if (jsonStr == null) return [];
    try {
      final decoded = json.decode(jsonStr);
      return (decoded as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[OfflineService] JSON解码失败（数据可能已损坏）: $e');
      return [];
    }
  }

  /// 缓存一条位置记录（无网络时调用）
  Future<void> cacheLocation(double lng, double lat, double speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getString(_cacheKey);
      final list = _safeDecodeList(cache);
      list.add({
        'lng': lng, 'lat': lat, 'speed': speed,
        'timestamp': DateTime.now().toIso8601String(),
      });
      // 最多保留500条
      while (list.length > 500) {
        list.removeAt(0);
      }
      await prefs.setString(_cacheKey, json.encode(list));
    } catch (e) {
      debugPrint('[OfflineService] 缓存位置失败: $e');
    }
  }

  /// 缓存一次打卡（无网络时调用）
  Future<void> cacheCheckin(String type, double lng, double lat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getString(_pendingCheckinKey);
      final list = _safeDecodeList(cache);
      list.add({ 'type': type, 'lng': lng, 'lat': lat, 'timestamp': DateTime.now().toIso8601String() });
      await prefs.setString(_pendingCheckinKey, json.encode(list));
    } catch (e) {
      debugPrint('[OfflineService] 缓存打卡失败: $e');
    }
  }

  /// 尝试同步离线数据
  Future<int> syncAll() async {
    int synced = 0;
    final token = _auth.token;
    if (token == null) return 0;

    final prefs = await SharedPreferences.getInstance();
    // 每次同步创建独立Dio实例，避免与ApiService共享拦截器链（Token刷新/熔断等逻辑可能干扰离线同步）
    final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
    final options = Options(headers: {'Authorization': 'Bearer $token'});

    // 同步定位数据（批量提交）
    final locCache = prefs.getString(_cacheKey);
    if (locCache != null) {
      final list = _safeDecodeList(locCache);
      // 转换为批量格式：ISO字符串→毫秒时间戳
      final points = list.map((item) => {
        'lng': item['lng'],
        'lat': item['lat'],
        'speed': item['speed'] ?? 0,
        'timestamp': item['timestamp'] != null
            ? DateTime.parse(item['timestamp'] as String).millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      }).toList();
      try {
        await dio.post(AppConfig.apiBatchLocation, data: {'points': points}, options: options);
        synced = points.length;
        await prefs.remove(_cacheKey);
      } catch (_) {
        // 网络仍然不可用就停止
      }
    }

    // 同步打卡数据 — 逐条同步，只清除确已成功的记录
    final checkinCache = prefs.getString(_pendingCheckinKey);
    if (checkinCache != null) {
      final list = _safeDecodeList(checkinCache);
      final remaining = <Map<String, dynamic>>[];
      int checkinSynced = 0;
      for (final item in list) {
        try {
          await dio.post(AppConfig.apiCheckin, data: item, options: options);
          checkinSynced++;
        } catch (_) {
          // 本条同步失败，保留剩余待同步
          remaining.add(item);
        }
      }
      if (remaining.isEmpty) {
        await prefs.remove(_pendingCheckinKey);
      } else {
        await prefs.setString(_pendingCheckinKey, json.encode(remaining));
      }
      synced += checkinSynced;
    }

    return synced;
  }

  /// 检查是否有离线缓存
  Future<bool> hasOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_cacheKey) || prefs.containsKey(_pendingCheckinKey);
  }

  /// 获取离线缓存条数
  Future<int> offlineCount() async {
    final prefs = await SharedPreferences.getInstance();
    final loc = prefs.getString(_cacheKey);
    final chk = prefs.getString(_pendingCheckinKey);
    int count = 0;
    if (loc != null) count += (json.decode(loc) as List).length;
    if (chk != null) count += (json.decode(chk) as List).length;
    return count;
  }
}

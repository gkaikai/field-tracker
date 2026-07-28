// 定位数据批量上传器
//
// 策略：
//   1. 攒够 N 条后批量POST上传，减少网络请求次数
//   2. 无网络时缓存到本地文件，恢复后自动补传
//   3. 最多每60秒强制上传一次（避免定位数据延迟过大）

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/location_point.dart';
import '../config/amap_key.dart';
import '../config/app_config.dart';

class LocationUploader {
  static final LocationUploader _instance = LocationUploader._();
  factory LocationUploader() => _instance;
  LocationUploader._();

  /// 认证失效回调（供 UI 层跳转登录页）
  void Function()? onAuthError;

  final Queue<LocationPoint> _pendingBatch = Queue<LocationPoint>();
  Dio? _dio;

  Timer? _flushTimer;
  bool _uploading = false;
  int _nextId = 1;
  String? _userId;
  String _cacheDir = Directory.systemTemp.path; // 默认值，init后替换为应用私有目录

  /// 缓存文件路径（以userId区分，避免多用户同设备混用）
  File get _cacheFile {
    if (_userId != null && _userId!.isNotEmpty) {
      return File('$_cacheDir/field_tracker_loc_$_userId.json');
    }
    return File('$_cacheDir/field_tracker_location_cache.json');
  }

  /// 设置当前用户ID（登录后调用），缓存文件路径自动切换
  void setUserId(String userId) => _userId = userId;

  /// 设置认证 Token（登录后调用）
  void setToken(String token) {
    _dio?.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 更新服务器地址（用户手动设置后调用）
  void updateBaseUrl(String url) {
    _dio?.options.baseUrl = url;
  }

  // ============================================================
  //  初始化
  // ============================================================
  Future<void> init() async {
    // 防止重复初始化导致定时器泄漏
    _flushTimer?.cancel();

    // 用应用私有目录代替系统临时目录（系统不会自动清理）
    final dir = await getApplicationDocumentsDirectory();
    _cacheDir = dir.path;

    // 初始化Dio
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    // 从文件恢复已缓存的记录，确定下一个 id
    final records = await _readAll();
    _nextId = records.isEmpty
        ? 1
        : records.map((r) => r['id'] as int).reduce((a, b) => a > b ? a : b) + 1;

    // 定时强制上传（每60秒）
    _flushTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => flushCache(),
    );
  }

  // ============================================================
  //  添加位置到缓存队列
  // ============================================================
  Future<void> enqueue(LocationPoint point) async {
    if (_pendingBatch.length >= 1000) {
      _pendingBatch.removeFirst(); // Queue.removeFirst = O(1)
    }
    _pendingBatch.addLast(point);

    // 攒够一批立即触发 flush
    if (_dio != null && _pendingBatch.length >= AMapConfig.uploadBatchSize) {
      await flushCache();
    }
  }

  // ============================================================
  //  上传缓存数据
  // ============================================================
  Future<void> flushCache() async {
    if (_uploading) return;
    _uploading = true;

    try {
      // 快照+立即清空，消除与 enqueue 的竞态
      final batch = List<LocationPoint>.from(_pendingBatch);
      _pendingBatch.clear();

      if (batch.isNotEmpty) {
        final records = await _readAll();
        for (final point in batch) {
          records.add({
            'id': _nextId++,
            ...point.toDbMap(),
          });
        }
        await _writeAll(records);
      }

      await _uploadFromFile();
    } catch (e) {
      // 上传失败不要紧，留在缓存里下次继续
    } finally {
      _uploading = false;
    }

    // 释放锁后如果积压了足够数据，立即再刷一次
    if (!_uploading && _pendingBatch.length >= AMapConfig.uploadBatchSize) {
      flushCache();
    }
  }

  // ============================================================
  //  批量上传到服务器
  // ============================================================
  Future<bool> _uploadBatch(List<LocationPoint> points) async {
    if (points.isEmpty || _dio == null) return true;

    try {
      final response = await _dio!.post(
        '/api/v1/location/batch',
        data: {
          'points': points.map((p) => p.toJson()).toList(),
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        onAuthError?.call();
      }
      return false;
    }
  }

  Future<void> _uploadFromFile() async {
    final records = await _readAll();
    final unuploaded = records.where((r) => r['uploaded'] == 0).toList();
    if (unuploaded.isEmpty) return;

    // 取最多100条
    final batch = unuploaded.take(100).toList();

    // 标记为已上传（先标记防重复）
    for (final record in batch) {
      record['uploaded'] = 1;
    }
    await _writeAll(records);

    // 转换成 LocationPoint 上传
    final points = batch.map((row) {
      return LocationPoint(
        userId: row['user_id'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        accuracy: (row['accuracy'] as num?)?.toDouble(),
        speed: (row['speed'] as num?)?.toDouble(),
        battery: (row['battery'] as num?)?.toDouble(),
        timestamp: DateTime.parse(row['recorded_at'] as String),
      );
    }).toList();

    final success = await _uploadBatch(points);
    if (success) {
      // 删除已上传的记录
      final remaining = records.where((r) => r['uploaded'] == 0).toList();
      await _writeAll(remaining);
    } else {
      // 失败则恢复标记
      for (final record in batch) {
        record['uploaded'] = 0;
      }
      await _writeAll(records);
    }
  }

  // ============================================================
  //  文件读写
  // ============================================================
  Future<List<Map<String, dynamic>>> _readAll() async {
    try {
      if (!await _cacheFile.exists()) return [];
      final content = await _cacheFile.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> list = json.decode(content);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<Map<String, dynamic>> records) async {
    try {
      await _cacheFile.writeAsString(json.encode(records));
    } catch (_) {
      // 写入失败不抛异常
    }
  }

  // ============================================================
  //  获取缓存数量（用于 UI 显示）
  // ============================================================
  Future<int> getCacheCount() async {
    try {
      final records = await _readAll();
      return records.where((r) => r['uploaded'] == 0).length;
    } catch (_) {
      return 0;
    }
  }

  /// 释放资源
  void dispose() {
    _flushTimer?.cancel();
  }
}

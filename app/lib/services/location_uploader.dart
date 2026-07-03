// 定位数据批量上传器
//
// 策略：
//   1. 攒够 N 条后批量POST上传，减少网络请求次数
//   2. 无网络时缓存到本地文件，恢复后自动补传
//   3. 最多每60秒强制上传一次（避免定位数据延迟过大）

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/location_point.dart';
import '../config/amap_key.dart';

class LocationUploader {
  static final LocationUploader _instance = LocationUploader._();
  factory LocationUploader() => _instance;
  LocationUploader._();

  /// 认证失效回调（供 UI 层跳转登录页）
  void Function()? onAuthError;

  final List<LocationPoint> _pendingBatch = [];
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AMapConfig.serverBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Timer? _flushTimer;
  bool _uploading = false;
  int _nextId = 1;

  /// 缓存文件路径
  File get _cacheFile => File(
        '${Directory.systemTemp.path}/field_tracker_location_cache.json',
      );

  /// 设置认证 Token（登录后调用）
  void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  // ============================================================
  //  初始化
  // ============================================================
  Future<void> init() async {
    // 防止重复初始化导致定时器泄漏
    _flushTimer?.cancel();

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
    _pendingBatch.add(point);

    // 写入文件缓存（双重保险）
    try {
      final record = {
        'id': _nextId++,
        ...point.toDbMap(),
      };
      final records = await _readAll();
      records.add(record);
      await _writeAll(records);
    } catch (_) {
      // 文件写入失败不影响定位主流程
    }

    // 攒够一批或达到时间，立即上传
    if (_pendingBatch.length >= AMapConfig.uploadBatchSize) {
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
      // 1. 上传内存中的待发批次
      if (_pendingBatch.isNotEmpty) {
        await _uploadBatch(_pendingBatch.toList());
        _pendingBatch.clear();
      }

      // 2. 上传文件中未上传的记录
      await _uploadFromFile();
    } catch (e) {
      // 上传失败不要紧，留在缓存里下次继续
    } finally {
      _uploading = false;
    }
  }

  // ============================================================
  //  批量上传到服务器
  // ============================================================
  Future<bool> _uploadBatch(List<LocationPoint> points) async {
    if (points.isEmpty) return true;

    try {
      final response = await _dio.post(
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

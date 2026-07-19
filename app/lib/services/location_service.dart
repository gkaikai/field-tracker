import 'dart:async';
import 'dart:collection';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import '../utils/geo_convert.dart';

/// 定位服务 — 使用 Geolocator（兼容HarmonyOS）+ 高精度GPS
///
/// 改进（v2）：
///   - 位置缓存队列（去噪 + 平滑）
///   - 高频上报（每15秒 或 缓存满5条即上报）
///   - 精度校验（accuracy>100m剔除）
///   - 简单滑动平均滤波
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();

  // 当前位置
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _uploadTimer;
  bool _isRunning = false;

  // 位置缓存队列（用于去噪 + 平滑 + 批量上报）
  final Queue<_PositionRecord> _positionBuffer = Queue();
  static const int _maxBufferSize = 5;       // 缓存满5条立即上报
  static const int _uploadIntervalSec = 12;   // 每12秒上报一次
  static const double _maxAcceptableAccuracy = 100.0; // 精度超过100米跳过

  // 性能统计
  int _totalPositions = 0;
  int _rejectedPositions = 0;
  double _bestAccuracy = 999;

  // 回调
  void Function(double lat, double lng, double accuracy, double? speed)? onLocationChanged;
  void Function(String error)? onError;

  LocationService._internal();

  double? get currentLat => _currentPosition?.latitude;
  double? get currentLng => _currentPosition?.longitude;
  double? get currentAccuracy => _currentPosition?.accuracy;
  bool get isRunning => _isRunning;
  int get totalPositions => _totalPositions;
  int get rejectedPositions => _rejectedPositions;
  double get bestAccuracy => _bestAccuracy;

  /// 启动持续定位
  Future<bool> startTracking() async {
    if (_isRunning) return true;

    // 1. 检查定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      onError?.call('定位权限被拒绝');
      return false;
    }

    // 2. 检查GPS
    final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isGpsEnabled) {
      onError?.call('请开启GPS定位');
      return false;
    }

    // 3. 获取一次高精度GPS位置（确保第一次定位就有数据）
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
      if (pos != null) {
        // WGS-84 → GCJ-02 转换
        final (gcjLat, gcjLng) = wgs84ToGcj02(pos.latitude, pos.longitude);
        final converted = Position(
          latitude: gcjLat,
          longitude: gcjLng,
          timestamp: pos.timestamp,
          accuracy: pos.accuracy,
          altitude: pos.altitude,
          heading: pos.heading,
          speed: pos.speed,
          speedAccuracy: pos.speedAccuracy,
          altitudeAccuracy: pos.altitudeAccuracy,
          headingAccuracy: pos.headingAccuracy,
        );
        _currentPosition = converted;
        _addToBuffer(converted);
      }
    } catch (e) {
      // 首次定位失败不阻止继续
    }

    // 4. 持续监听位置变化（精度最高，距离过滤0米）
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,       // 每一米都触发更新
        timeLimit: null,
      ),
    ).listen(
      (Position position) {
        _totalPositions++;

        // 精度校验
        if (position.accuracy > _maxAcceptableAccuracy) {
          _rejectedPositions++;
          return; // 精度太差，跳过
        }

        // WGS-84 → GCJ-02 转换
        final (gcjLat, gcjLng) = wgs84ToGcj02(position.latitude, position.longitude);
        final converted = Position(
          latitude: gcjLat,
          longitude: gcjLng,
          timestamp: position.timestamp,
          accuracy: position.accuracy,
          altitude: position.altitude,
          heading: position.heading,
          speed: position.speed,
          speedAccuracy: position.speedAccuracy,
          altitudeAccuracy: position.altitudeAccuracy,
          headingAccuracy: position.headingAccuracy,
        );

        // 更新最佳精度记录
        if (converted.accuracy < _bestAccuracy) {
          _bestAccuracy = converted.accuracy;
        }

        _currentPosition = converted;
        _addToBuffer(converted);

        // 对外回调
        onLocationChanged?.call(
          converted.latitude,
          converted.longitude,
          converted.accuracy,
          converted.speed,
        );
      },
      onError: (error) {
        onError?.call('定位流错误: $error');
      },
    );

    // 5. 定时上报位置（每12秒）
    _uploadTimer = Timer.periodic(
      const Duration(seconds: _uploadIntervalSec),
      (_) => _flushBuffer(),
    );

    _isRunning = true;
    return true;
  }

  /// 停止定位
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _positionBuffer.clear();
    _isRunning = false;
    _currentPosition = null;
  }

  // ===================================================================
  //  位置缓存 & 上报
  // ===================================================================

  /// 将位置加入缓存（满maxBufferSize自动上报）
  void _addToBuffer(Position pos) {
    _positionBuffer.add(_PositionRecord(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      speed: pos.speed,
      timestamp: pos.timestamp.millisecondsSinceEpoch,
    ));

    if (_positionBuffer.length >= _maxBufferSize) {
      _flushBuffer();
    }
  }

  /// 刷新缓存（上报 + 清空）
  Future<void> _flushBuffer() async {
    if (_positionBuffer.isEmpty) return;

    final batch = _positionBuffer.toList();
    _positionBuffer.clear();

    // 取最后一条作为"当前位置"
    final last = batch.last;

    // 平滑处理取均值（消除GPS抖动）
    final avgLat = batch.map((p) => p.lat).reduce((a, b) => a + b) / batch.length;
    final avgLng = batch.map((p) => p.lng).reduce((a, b) => a + b) / batch.length;
    final avgAccuracy = batch.map((p) => p.accuracy).reduce((a, b) => a + b) / batch.length;

    try {
      await _api.post(AppConfig.apiReportLocation, data: {
        'lng': avgLng,
        'lat': avgLat,
        'accuracy': avgAccuracy,
        'speed': last.speed ?? 0,
        'timestamp': last.timestamp,
        'batch_size': batch.length,
      });
    } catch (_) {
      // 网络失败静默处理
    }

    // 围栏检测（用平滑后的坐标）
    try {
      await _api.post('/api/v1/fences/auto-check', data: {
        'lat': avgLat,
        'lng': avgLng,
      });
    } catch (_) {}
  }

  /// 获取最新一次位置
  Future<Position?> getLastKnownPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        _currentPosition = pos;
      }
      return pos;
    } catch (_) {
      return _currentPosition;
    }
  }
}

/// 位置缓存记录
class _PositionRecord {
  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final int timestamp;

  const _PositionRecord({
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.speed,
    required this.timestamp,
  });
}

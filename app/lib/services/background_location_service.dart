/// 后台定位服务 — 使用前台服务保活，后台持续采集GPS
///
/// 原理：
/// 1. flutter_background_service 创建 Android Foreground Service
/// 2. 服务显示一个持久通知（系统不会杀前台服务）
/// 3. 在后台隔离区运行 Geolocator 持续监听位置
/// 4. 每12秒上报一次到服务器
///
/// HarmonyOS/华为特殊处理：
/// - 使用 isIgnoreBatteryOptimizations 引导用户加入白名单
/// - 前台服务通知无法被系统静默杀死

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 服务端地址（从环境配置同步）
const String _serverBaseUrl = 'https://f8b09e58fb70b846-123-123-97-213.serveousercontent.com';

/// 初始化后台定位服务
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // 每次启动时自动重启
      autoStart: false,
      autoStartOnBoot: false,
      // 前台服务标识
      notificationChannelId: 'location_tracking_channel',
      initialNotificationContent: '正在采集位置信息...',
      initialNotificationTitle: '外勤定位',
      // 启动后是否显示通知
      foregroundServiceNotificationId: 888,
      // 前台服务类型（Android 14+ 需要）
      foregroundServiceTypes: [AndroidForegroundType.location],
      // 回调函数
      onStart: onStart,
      // 是否在前台服务中运行
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// iOS后台回调（必须返回true）
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

/// 服务启动入口（在后台隔离区运行）
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android前台服务 — 设置通知交互
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 定时更新通知内容
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: '外勤定位运行中',
        content: '正在采集轨迹数据...',
      );
    }
  });

  // 确保服务持续运行（Android前台模式）
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // ===== 开始采集定位 =====
  // 先获取一次高精度位置
  try {
    await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 15),
    );
  } catch (_) {}

  // 持续监听位置
  StreamSubscription<Position>? subscription;
  List<Map<String, dynamic>> _buffer = [];
  Timer? _uploadTimer;

  subscription = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: null,
    ),
  ).listen(
    (Position position) {
      if (position.accuracy > 100) return; // 精度太差跳过

      _buffer.add({
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed ?? 0,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
      });

      // 缓存满5条立即上报
      if (_buffer.length >= 5) {
        _flushBuffer(_buffer);
        _buffer.clear();
      }
    },
    onError: (error) {},
  );

  // 每12秒定时上报
  _uploadTimer = Timer.periodic(const Duration(seconds: 12), (_) {
    if (_buffer.isNotEmpty) {
      _flushBuffer(_buffer);
      _buffer.clear();
    }
  });

  // 监听服务停止事件
  service.on('stopService').listen((event) {
    _uploadTimer?.cancel();
    subscription?.cancel();
    service.stopSelf();
  });
}

/// 上报位置到服务器
Future<void> _flushBuffer(List<Map<String, dynamic>> buffer) async {
  if (buffer.isEmpty) return;

  final last = buffer.last;
  final avgLat = buffer.fold<double>(0, (sum, p) => sum + (p['lat'] as double)) / buffer.length;
  final avgLng = buffer.fold<double>(0, (sum, p) => sum + (p['lng'] as double)) / buffer.length;
  final avgAcc = buffer.fold<double>(0, (sum, p) => sum + (p['accuracy'] as double)) / buffer.length;

  // 从SharedPreferences读取token
  String? token;
  try {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
  } catch (_) {}

  try {
    await Dio().post(
      '$_serverBaseUrl/api/v1/location/report',
      data: {
        'lng': avgLng,
        'lat': avgLat,
        'accuracy': avgAcc,
        'speed': last['speed'] ?? 0,
        'timestamp': last['timestamp'],
        'batch_size': buffer.length,
      },
      options: Options(
        headers: {'Authorization': 'Bearer ${token ?? ""}'},
        connectTimeout: const Duration(seconds: 10),
      ),
    );
  } catch (_) {
    // 网络失败静默
  }
}

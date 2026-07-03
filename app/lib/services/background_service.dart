// 后台保活服务
//
// 核心策略:
//   1. Foreground Service（Android）- 前台服务 + 持久通知，系统几乎不会杀
//   2. WorkManager（Android）- 周期性唤醒，系统重启后自动恢复注册
//   3. Background Fetch（iOS）- 定时后台唤醒（约15分钟间隔）
//   4. 国产ROM引导 - 检测机型并提示用户加入白名单
//
// 注意：
//   后台保活不能通过代码绕过系统限制，必须引导用户手动授权。
//   _onStart / _onIosBackground 运行在独立 isolate，不能直接访问主 isolate 的 singleton。
//   跨 isolate 通信通过 SharedPreferences 桥接。

import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 任务名称
const String kUploadTaskName = 'com.fieldtracker.location.upload';

/// SharedPreferences key
const String _kIsRunning = 'bg_tracker_running';
const String _kModeLabel = 'bg_tracker_mode';

/// 后台服务
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._();
  factory BackgroundService() => _instance;
  BackgroundService._();

  bool _initialized = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  // ============================================================
  //  初始化（应用启动时调用一次）
  // ============================================================
  Future<void> initialize() async {
    if (_initialized) return;

    // 1. 初始化通知渠道（前台服务的通知必须）
    final notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'location_tracker_channel',
            '位置追踪',
            description: '显示定位状态',
            importance: Importance.low,
          ),
        );

    // 2. 配置前台服务
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'location_tracker_channel',
        initialNotificationTitle: '位置追踪中',
        initialNotificationContent: '正在记录您的实时位置',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    // 3. 注册 WorkManager（Android 周期性任务，重启后自动恢复）
    await Workmanager().registerPeriodicTask(
      kUploadTaskName,
      kUploadTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      initialDelay: const Duration(minutes: 1),
    );

    _initialized = true;
  }

  /// 保存运行状态到 SharedPreferences（供后台 isolate 读取）
  static Future<void> saveRunningState({required bool running, String mode = '省电模式'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsRunning, running);
    await prefs.setString(_kModeLabel, mode);
  }

  // ============================================================
  //  启动 / 停止 前台服务
  // ============================================================
  Future<void> start() async {
    if (_isRunning) return;
    final service = FlutterBackgroundService();
    await service.startService();
    _isRunning = true;
    await saveRunningState(running: true);
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    _isRunning = false;
    await saveRunningState(running: false);
  }

  /// 更新模式标签（供 LocationService 模式切换时调用）
  static Future<void> updateModeLabel(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeLabel, mode);
  }

  // ============================================================
  //  Foreground Service 入口（运行在后台 isolate）
  // ============================================================
  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        service.stopSelf();
      }, onError: (e) {
        // 监听失败不影响前台服务
      });

      Timer.periodic(const Duration(seconds: 30), (timer) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final isRunning = prefs.getBool(_kIsRunning) ?? false;
          if (isRunning) {
            final mode = prefs.getString(_kModeLabel) ?? '省电模式';
            service.setForegroundNotificationInfo(
              title: '位置追踪中',
              content: '模式: $mode',
            );
            service.setAsForegroundService();
          } else {
            timer.cancel();
          }
        } catch (_) {
          // SharedPreferences 读取失败不影响前台服务
        }
      });
    }
  }

  // ============================================================
  //  iOS 后台唤醒（约30秒执行窗口，同一进程内回调）
  // ============================================================
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isRunning = prefs.getBool(_kIsRunning) ?? false;
      if (isRunning) {
        // iOS background fetch: 上传缓存数据
        // 此处不能访问 Dio/DB 单例，实际生产环境通过 MethodChannel
        // 通知主 isolate 执行上传
      }
    } catch (_) {
      // 静默失败
    }
    return true;
  }
}

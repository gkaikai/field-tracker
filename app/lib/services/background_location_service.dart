// 原生定位前台服务接口
//
// 通过 MethodChannel 调用 Android 原生 ForegroundService
// 原生服务使用AMapLocationClient采集GPS（此进程唯一的AMap实例）
// 数据通过 onLocationUpdate 通道送回 Flutter
//
// 架构：单一AMapLocationClient在ForegroundService中运行，
// 同时服务：原生HTTP上传 + Flutter地图显示。

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show debugPrint;
import '../config/app_config.dart';
import '../services/auth_service.dart';

const MethodChannel _channel = MethodChannel('com.fieldtracker/location_service');

/// ⚠️ 全局变量：可被任何调用方覆盖，多实例场景下存在竞态风险。
/// 当前设计中仅由 AmapLocationService 在初始化时赋值一次，不应被其他模块重新赋值。
void Function(double lat, double lng, double accuracy, double speed, int timestamp)? onNativeLocationUpdate;

/// 启动前台定位服务（通知栏 + WakeLock + 高德AMapLocationClient）
Future<bool> startBackgroundLocationService() async {
  try {
    // 先传配置再启动服务，避免定时器先于配置跑起来
    await _passServerConfigToNative();
    await _channel.invokeMethod('startService');
    return true;
  } catch (e) {
    debugPrint('[后台服务] startService 启动失败: $e (type: ${e.runtimeType})');
    return false;
  }
}

/// 将服务器地址和Token传给原生层（原生HTTP上传已关闭，保留供恢复时使用）
Future<void> _passServerConfigToNative() async {
  try {
    final auth = AuthService();
    final token = auth.token ?? '';
    await _channel.invokeMethod('setServerConfig', {
      'url': AppConfig.baseUrl,
      'token': token,
    });
    debugPrint('[后台服务] 原生上传配置已下发: ${AppConfig.baseUrl}');
  } catch (e) {
    debugPrint('[后台服务] 下发配置失败: $e');
  }
}

/// 停止前台定位服务
Future<bool> stopBackgroundLocationService() async {
  try {
    await _channel.invokeMethod('stopService');
    return true;
  } catch (e) {
    debugPrint('[后台服务] 停止失败: $e');
    return false;
  }
}

/// 动态调整原生GPS采集间隔
Future<void> setNativeGpsInterval(int intervalMs) async {
  try {
    await _channel.invokeMethod('setGpsInterval', {'intervalMs': intervalMs});
    debugPrint('[后台服务] GPS间隔已设为 ${intervalMs}ms');
  } catch (e) {
    debugPrint('[后台服务] 设置GPS间隔失败: $e');
  }
}

/// 设置原生定位回调监听（在 amap_location_service 启动时调用）
void setupNativeLocationCallback() {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onLocationUpdate') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null) {
        final lat = (args['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (args['lng'] as num?)?.toDouble() ?? 0.0;
        final accuracy = (args['accuracy'] as num?)?.toDouble() ?? 0.0;
        final speed = (args['speed'] as num?)?.toDouble() ?? 0.0;
        final timestamp = (args['timestamp'] as num?)?.toInt() ?? 0;
        onNativeLocationUpdate?.call(lat, lng, accuracy, speed, timestamp);
      }
    }
    return null;
  });
}

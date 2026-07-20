/// 原生定位前台服务接口
///
/// 通过 MethodChannel 调用 Android 原生 ForegroundService
/// 原生服务直接在 Java 层用 FusedLocationProviderClient 采集 GPS
/// 不需要 Flutter 后台隔离区，避免了插件不可用的问题

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('com.fieldtracker/location_service');

/// 启动后台前台服务（会在通知栏显示"外勤定位运行中"）
Future<bool> startBackgroundLocationService() async {
  try {
    await _channel.invokeMethod('startService');
    return true;
  } catch (e) {
    print('[后台服务] 启动失败: $e');
    return false;
  }
}

/// 停止后台前台服务
Future<bool> stopBackgroundLocationService() async {
  try {
    await _channel.invokeMethod('stopService');
    return true;
  } catch (e) {
    print('[后台服务] 停止失败: $e');
    return false;
  }
}

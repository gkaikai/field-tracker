/// Android 系统设置快捷跳转工具
/// 提供"点一下直接跳到对应系统设置页"的能力
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 系统设置跳转
class SystemSettings {
  static const _channel = MethodChannel('com.fieldtracker/location_service');

  /// 打开本应用的系统设置详情页（定位/存储权限等都在此处设置）
  static Future<bool> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
      return true;
    } catch (e) {
      debugPrint('[SystemSettings] 打开应用设置失败: $e');
      return false;
    }
  }

  /// 请求忽略电池优化（让系统不在后台杀APP定位）
  static Future<bool> requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('openBatteryOptimization');
      return true;
    } catch (e) {
      debugPrint('[SystemSettings] 打开电池优化设置失败: $e');
      return false;
    }
  }
}

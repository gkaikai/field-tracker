/// 时间工具函数 — 统一的时间格式化
library;
import 'package:flutter/foundation.dart' show debugPrint;

/// 格式化服务器返回的 ISO 时间戳为本地时间字符串
/// 适配带 `Z` 后缀的 TIMESTAMPTZ 和不带后缀的 TIMESTAMP
/// 统一使用 dt.toLocal() 正确处理时区
String formatTimestamp(String? timestamp, {bool showDate = false, bool showSeconds = false}) {
  if (timestamp == null) return '--';
  try {
    final dt = DateTime.parse(timestamp);
    final local = dt.toLocal(); // 正确识别时区偏移
    if (showDate) {
      return '${local.month}/${local.day} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
          '${showSeconds ? ':${local.second.toString().padLeft(2, '0')}' : ''}';
    }
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  } catch (e) {
    debugPrint('[formatTimestamp] 解析失败: $e');
    return timestamp;
  }
}

/// 格式化服务器返回的 ISO 时间戳为完整本地日期时间字符串
String formatDateTimeFull(String? timestamp) {
  return formatTimestamp(timestamp, showDate: true, showSeconds: true);
}

/// 格式化服务器返回的 ISO 时间戳为日期字符串 (yyyy-MM-dd)
String formatDate(String? timestamp) {
  if (timestamp == null) return '--';
  try {
    final dt = DateTime.parse(timestamp);
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  } catch (e) {
    return timestamp;
  }
}

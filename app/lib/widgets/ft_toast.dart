/// 统一 Toast 反馈工具 — 替代散落的 SnackBar 硬编码
library;
import 'package:flutter/material.dart';

/// Toast 类型
enum FTToastType {
  success,
  error,
  warning,
  info,
}

/// 统一 Toast 工具
class FTToast {
  /// 显示 Toast
  static void show(
    BuildContext context, {
    required String message,
    FTToastType type = FTToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colors = _colors(type);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_icon(type), color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    onAction();
                  },
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
          backgroundColor: colors.background,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: type == FTToastType.error
              ? const Duration(seconds: 6)
              : duration,
          dismissDirection: DismissDirection.horizontal,
        ),
      );
  }

  /// 快捷方法
  static void success(BuildContext context, String message, {String? action, VoidCallback? onAction}) =>
      show(context, message: message, type: FTToastType.success, actionLabel: action, onAction: onAction);

  static void error(BuildContext context, String message, {String? action, VoidCallback? onAction}) =>
      show(context, message: message, type: FTToastType.error, actionLabel: action, onAction: onAction);

  static void warning(BuildContext context, String message, {String? action, VoidCallback? onAction}) =>
      show(context, message: message, type: FTToastType.warning, actionLabel: action, onAction: onAction);

  static void info(BuildContext context, String message, {String? action, VoidCallback? onAction}) =>
      show(context, message: message, type: FTToastType.info, actionLabel: action, onAction: onAction);

  // ===== 内部 =====
  static _ToastColors _colors(FTToastType type) {
    switch (type) {
      case FTToastType.success: return _ToastColors(background: const Color(0xFF16A34A));
      case FTToastType.error: return _ToastColors(background: const Color(0xFFDC2626));
      case FTToastType.warning: return _ToastColors(background: const Color(0xFFF59E0B));
      case FTToastType.info: return _ToastColors(background: const Color(0xFF0EA5E9));
    }
  }

  static IconData _icon(FTToastType type) {
    switch (type) {
      case FTToastType.success: return Icons.check_circle;
      case FTToastType.error: return Icons.error;
      case FTToastType.warning: return Icons.warning_amber;
      case FTToastType.info: return Icons.info_outline;
    }
  }
}

class _ToastColors {
  final Color background;
  const _ToastColors({required this.background});
}

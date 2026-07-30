/// 空状态组件 — 插画 + 标题 + 描述 + 操作按钮
library;
import 'package:flutter/material.dart';

class FTEmptyState extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FTEmptyState({
    super.key,
    required this.icon,
    this.iconBackground = const Color(0xFFEFF6FF),
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: iconBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空状态预定义工厂
class FTEmpty {
  static Widget attendance(VoidCallback onAction) => FTEmptyState(
    icon: Icons.history,
    iconBackground: const Color(0xFFF0FDF4),
    title: '暂无打卡记录',
    subtitle: '今天还没有打卡记录',
    actionLabel: '去打卡',
    onAction: onAction,
  );

  static Widget track(VoidCallback onAction) => FTEmptyState(
    icon: Icons.route,
    iconBackground: const Color(0xFFFFF7ED),
    title: '暂无运动轨迹',
    subtitle: '今天还没有轨迹数据',
    actionLabel: '查看地图',
    onAction: onAction,
  );

  static Widget photo(VoidCallback onAction) => FTEmptyState(
    icon: Icons.camera_alt,
    iconBackground: const Color(0xFFF5F3FF),
    title: '暂无照片',
    subtitle: '还没有拍摄照片',
    actionLabel: '去拍照',
    onAction: onAction,
  );

  static Widget report(VoidCallback onAction) => FTEmptyState(
    icon: Icons.assignment,
    iconBackground: const Color(0xFFF0F9FF),
    title: '暂无工作汇报',
    subtitle: '还没有提交工作汇报',
    actionLabel: '写汇报',
    onAction: onAction,
  );

  static Widget message() => const FTEmptyState(
    icon: Icons.notifications_none,
    title: '暂无消息',
    subtitle: '暂时没有新的通知',
  );
}

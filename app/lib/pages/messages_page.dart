// 消息通知页面
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/ft_empty_state.dart';
import 'approval_page.dart';

/// 消息未读数共享状态 — MainShell 监听此值更新底部徽标
final ValueNotifier<int> messagesUnreadCount = ValueNotifier<int>(0);

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final ApiService _api = ApiService();
  List _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.get('/api/v1/messages');
      final msgs = (resp.data['messages'] as List?) ?? [];
      final unread = msgs.where((m) {
        if (m is Map) return m['read'] == false;
        return false;
      }).length;
      messagesUnreadCount.value = unread;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
    } catch (_) {
      // 用模拟数据展示 UI
      final mock = _mockMessages();
      messagesUnreadCount.value = mock.where((m) => m['read'] == false).length;
      setState(() {
        _messages = mock;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mockMessages() => [
    {'type': 'checkin', 'title': '打卡成功', 'body': '您已成功签到 08:30:15', 'time': '5分钟前', 'read': false},
    {'type': 'approval', 'title': '审批通知', 'body': '您的事假申请已通过', 'time': '2小时前', 'read': false},
    {'type': 'fence', 'title': '围栏提醒', 'body': '您已进入「公司总部」围栏', 'time': '昨天', 'read': false},
    {'type': 'report', 'title': '工作提醒', 'body': '记得提交今日日报', 'time': '昨天', 'read': true},
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) return FTEmpty.message();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        itemCount: _messages.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, endIndent: 16),
        itemBuilder: (context, i) {
          final m = _messages[i] as Map<String, dynamic>;
          final icon = _typeIcon(m['type'] as String? ?? '');
          final color = _typeColor(m['type'] as String? ?? '');
          final isUnread = m['read'] == false;
          return ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Row(children: [
              Text(m['title'] ?? '', style: TextStyle(fontSize: 15, fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400)),
              if (isUnread) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle))],
            ]),
            subtitle: Text(m['body'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(m['time'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            onTap: () {
              if (m['type'] == 'approval') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalPage()));
              }
            },
          );
        },
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'checkin': return Icons.fingerprint;
      case 'approval': return Icons.approval;
      case 'fence': return Icons.fence;
      case 'report': return Icons.assignment;
      default: return Icons.notifications;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'checkin': return const Color(0xFF16A34A);
      case 'approval': return const Color(0xFFF59E0B);
      case 'fence': return const Color(0xFFDC2626);
      case 'report': return const Color(0xFF0EA5E9);
      default: return const Color(0xFF2563EB);
    }
  }
}

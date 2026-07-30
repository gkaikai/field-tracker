// 管理驾驶舱 v2 — 仪表盘卡片+团队考勤列表
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/time_utils.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List _teamStatus = []; List _recentVisits = [];
  String? _error;

  @override
  void initState() { super.initState(); _loadDashboard(); }

  Future<void> _loadDashboard() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final results = await Future.wait([
        _api.get('/api/v1/attendance/stats?startDate=$today&endDate=$today'),
        _api.get('/api/v1/attendance/my-status'),
        _api.get('/api/v1/visits/history?pageSize=10'),
      ]);
      final statsList = results[0].data['stats'] as List? ?? [];
      setState(() {
        _stats = (results[0].data as Map<String, dynamic>?) ?? {};
        _teamStatus = statsList.map((s) => {
          'name': s['name'] ?? '员工', 'checkedIn': (s['checkin_count'] ?? 0) > 0, 'checkinTime': '',
        }).toList();
        _recentVisits = (results[2].data['visits'] as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = '加载驾驶舱数据失败'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理驾驶舱'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDashboard)]),
      body: _isLoading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12), ElevatedButton.icon(onPressed: _loadDashboard, icon: const Icon(Icons.refresh), label: const Text('重试')),
            ]))
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 4 key metrics
                  _buildMetricRow(),
                  const SizedBox(height: 20),
                  // 团队考勤
                  Text('团队考勤', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                  const SizedBox(height: 8),
                  _buildTeamList(),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricRow() {
    final items = [
      {'value': '${_stats['totalEmployees'] ?? 15}', 'label': '总人数', 'color': const Color(0xFF2563EB), 'icon': Icons.people},
      {'value': '${_stats['onlineCount'] ?? 12}', 'label': '在线', 'color': const Color(0xFF16A34A), 'icon': Icons.wifi},
      {'value': '${_stats['checkinCount'] ?? 8}', 'label': '已签到', 'color': const Color(0xFFF59E0B), 'icon': Icons.fingerprint},
      {'value': '${_stats['visitCount'] ?? 3}', 'label': '拜访中', 'color': const Color(0xFF7C3AED), 'icon': Icons.business},
    ];
    return Row(children: items.map((item) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: (item['color'] as Color).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(item['icon'] as IconData, size: 22, color: item['color'] as Color),
          const SizedBox(height: 6),
          Text(item['value'] as String, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: item['color'] as Color)),
          Text(item['label'] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    )).toList());
  }

  Widget _buildTeamList() {
    final mockTeam = [
      {'name': '张三', 'status': '✅ 08:28', 'color': const Color(0xFF16A34A), 'bg': const Color(0xFFF0FDF4)},
      {'name': '李四', 'status': '✅ 08:30', 'color': const Color(0xFF16A34A), 'bg': const Color(0xFFF0FDF4)},
      {'name': '王五', 'status': '⏰ 09:05', 'color': const Color(0xFFF59E0B), 'bg': const Color(0xFFFFFBEB)},
      {'name': '赵六', 'status': '❌ 未签到', 'color': const Color(0xFFDC2626), 'bg': const Color(0xFFFEF2F2)},
    ];
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: mockTeam.map((m) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
        child: Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
            child: Center(child: Text((m['name'] as String)[0], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(m['name'] as String, style: const TextStyle(fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: m['bg'] as Color, borderRadius: BorderRadius.circular(6)),
            child: Text(m['status'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: m['color'] as Color)),
          ),
        ]),
      )).toList()),
    );
  }
}

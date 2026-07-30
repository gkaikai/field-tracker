// 管理员驾驶舱 — 团队仪表盘+监控概览
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
  List _teamStatus = [];
  List _recentVisits = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() { _isLoading = true; });
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final results = await Future.wait([
        _api.get('/api/v1/attendance/stats?startDate=$today&endDate=$today'),
        _api.get('/api/v1/attendance/my-status'),
        _api.get('/api/v1/visits/history?pageSize=10'),
      ]);
      setState(() {
        _stats = (results[0].data as Map<String, dynamic>?) ?? {};
        _teamStatus = [];
        // 尝试从stats中提取团队状态
        final statsList = results[0].data['stats'] as List? ?? [];
        _teamStatus = statsList.map((s) => {
          'name': s['name'] ?? '员工',
          'checkedIn': (s['checkin_count'] ?? 0) > 0,
          'checkinTime': '',
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
      appBar: AppBar(
        title: const Text('管理驾驶舱'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDashboard),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadDashboard,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // 出勤概览卡片
                  _buildStatsCard(),
                  const SizedBox(height: 12),
                  // 团队成员状态
                  _buildSectionTitle('👥 团队成员状态'),
                  const SizedBox(height: 4),
                  _buildTeamStatusList(),
                  const SizedBox(height: 12),
                  // 最新拜访记录
                  _buildSectionTitle('📋 最新拜访记录'),
                  const SizedBox(height: 4),
                  _buildRecentVisits(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(Icons.people, '${_stats['totalUsers'] ?? 0}', '总人数', Colors.blue),
                _statItem(Icons.check_circle, '${_stats['checkedIn'] ?? 0}', '已签到', Colors.green),
                _statItem(Icons.schedule, '${_stats['late'] ?? 0}', '迟到', Colors.orange),
                _statItem(Icons.cancel, '${_stats['absent'] ?? 0}', '未签到', Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(Icons.tour, '${_stats['todayVisits'] ?? 0}', '今日拜访', Colors.deepOrange),
                _statItem(Icons.pending_actions, '${_stats['pendingApprovals'] ?? 0}', '待审批', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildTeamStatusList() {
    if (_teamStatus.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey[400]))),
        ),
      );
    }
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: _teamStatus.take(10).map((m) {
          final member = m as Map<String, dynamic>;
          final checkedIn = member['checkedIn'] == true;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: checkedIn ? Colors.green[100] : Colors.red[100],
              child: Icon(Icons.person, size: 18, color: checkedIn ? Colors.green : Colors.red),
            ),
            title: Text(member['name'] ?? member['phone'] ?? '', style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              checkedIn ? '已签到 ${member['checkinTime'] ?? ''}' : '未签到',
              style: TextStyle(fontSize: 11, color: checkedIn ? Colors.green[600] : Colors.red[400]),
            ),
            trailing: member['lastLat'] != null
                ? Icon(Icons.my_location, size: 16, color: Colors.blue[300])
                : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentVisits() {
    if (_recentVisits.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: Text('暂无拜访记录', style: TextStyle(color: Colors.grey[400]))),
        ),
      );
    }
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: _recentVisits.take(5).map((v) {
          final visit = v as Map<String, dynamic>;
          final done = visit['status'] == 'completed';
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: done ? Colors.green[100] : Colors.orange[100],
              child: Icon(Icons.business, size: 16, color: done ? Colors.green : Colors.orange),
            ),
            title: Text(visit['customer_name'] ?? '', style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              done ? '已完成' : '进行中',
              style: TextStyle(fontSize: 11, color: done ? Colors.green[600] : Colors.orange[600]),
            ),
            trailing: visit['start_time'] != null
                ? Text(formatDate(visit['start_time'] as String?), style: TextStyle(fontSize: 11, color: Colors.grey[400]))
                : null,
          );
        }).toList(),
      ),
    );
  }
}

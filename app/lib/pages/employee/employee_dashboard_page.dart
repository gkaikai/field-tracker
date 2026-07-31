// 员工数据页 v2
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});
  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  final AuthService _auth = AuthService();
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final resp = await ApiService().get('/api/v1/attendance/my-status');
      if (mounted) setState(() { _data = resp.data as Map<String, dynamic>; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _auth.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('我的工作台')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
                    child: Center(child: Text((_auth.userName ?? '?')[0], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))))),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_auth.userName ?? '未登录', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(isAdmin ? '管理员视角' : '员工视角', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ]))),
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFF0FDF4),
                  child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _statItem('本月打卡', '${_data['monthlyCheckin'] ?? 0}', const Color(0xFF2563EB)),
                      _statItem('出勤天数', '${_data['workDays'] ?? 0}', const Color(0xFF16A34A)),
                      _statItem('总里程', '${_data['totalKm'] ?? 0}', const Color(0xFFF59E0B)),
                    ]),
                  ])),
                ),
              ]),
            ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    ]);
  }
}

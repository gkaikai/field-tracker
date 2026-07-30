// 打卡规则页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/amap_location_service.dart';
import '../services/route_guard.dart';

class AttendanceRulesPage extends StatefulWidget {
  const AttendanceRulesPage({super.key});
  @override
  State<AttendanceRulesPage> createState() => _AttendanceRulesPageState();
}

class _AttendanceRulesPageState extends State<AttendanceRulesPage> {
  final _api = ApiService();
  List _rules = []; bool _loading = true;

  @override
  void initState() { super.initState(); if (!RouteGuard.isAdmin()) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pushReplacementNamed(context, '/home'); }); return; } _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await _api.get('/api/v1/attendance/rules'); setState(() { _rules = (r.data['rules'] as List?) ?? []; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打卡规则'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showDialog())]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0F9FF), shape: BoxShape.circle), child: const Icon(Icons.checklist, size: 28, color: Color(0xFF0EA5E9))),
                  const SizedBox(height: 12), const Text('暂无打卡规则', style: TextStyle(fontSize: 15, color: Colors.grey)),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _rules.map((r) {
                    final rm = r as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(rm['name']?.toString() ?? '规则', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                              child: const Text('生效', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF16A34A))),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          _row('⏰', '上班', '${rm['startTime'] ?? '09:00'} - ${rm['lateTime'] ?? '09:30'}'),
                          _row('⏰', '下班', '${rm['endTime'] ?? '18:00'}'),
                          _row('📍', '方式', '位置 + WiFi'),
                          _row('📏', '范围', '${rm['radius'] ?? 100}m'),
                        ]),
                      ),
                    );
                  }).toList(),
                )),
    );
  }

  Widget _row(String icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 13)), const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
  }

  void _showDialog() {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: '09:00');
    final endCtrl = TextEditingController(text: '18:00');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建规则'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: startCtrl, decoration: const InputDecoration(labelText: '上班时间', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: endCtrl, decoration: const InputDecoration(labelText: '下班时间', border: OutlineInputBorder()))),
        ]),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), ElevatedButton(onPressed: () { Navigator.pop(ctx); _load(); }, child: const Text('保存'))],
    ));
  }
}

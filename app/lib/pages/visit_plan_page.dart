// 拜访计划页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VisitPlanPage extends StatefulWidget {
  const VisitPlanPage({super.key});
  @override
  State<VisitPlanPage> createState() => _VisitPlanPageState();
}

class _VisitPlanPageState extends State<VisitPlanPage> {
  final _api = ApiService();
  List _plans = []; bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await _api.get('/api/v1/visits/plans'); setState(() { _plans = (r.data['plans'] as List?) ?? []; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拜访计划'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showDialog)]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0FDF4), shape: BoxShape.circle), child: const Icon(Icons.business, size: 28, color: Color(0xFF16A34A))),
                  const SizedBox(height: 12), const Text('暂无拜访计划', style: TextStyle(fontSize: 15, color: Colors.grey)),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _plans.map((p) {
                    final pm = p as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.business, color: Color(0xFF2563EB))),
                        title: Text(pm['title']?.toString() ?? '拜访计划', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(pm['date']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                          child: Text(pm['status']?.toString() ?? '计划', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF2563EB)))),
                      ),
                    );
                  }).toList(),
                )),
    );
  }

  void _showDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建拜访计划'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(decoration: const InputDecoration(labelText: '客户名称', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(labelText: '拜访日期', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), ElevatedButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('创建'))],
    ));
  }
}

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

class VisitPlanPage extends StatefulWidget {
  const VisitPlanPage({super.key});
  @override
  State<VisitPlanPage> createState() => _VisitPlanPageState();
}

class _VisitPlanPageState extends State<VisitPlanPage> {
  final _auth = AuthService();
  List _plans = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final r = await dio.get('/api/v1/customers/visits',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _plans = r.data['visits'] ?? []; _loading = false; });
    } catch (e) { debugPrint('加载拜访计划失败: $e'); if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e'))); } }
  }

  void _showPlanDialog() {
    final customerCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateTime.now().toString().substring(0, 10));

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新增拜访计划'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: customerCtrl, decoration: const InputDecoration(labelText: '客户名称', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: '计划内容', border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 8),
        TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: '计划日期', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          if (customerCtrl.text.isEmpty) return;
          try {
            final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            await dio.post('/api/v1/customers/visit', data: {
              'customerId': 0, 'content': '【计划】${contentCtrl.text}',
              'lat': 0, 'lng': 0, 'address': '计划拜访: ${customerCtrl.text}',
            }, options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            Navigator.pop(ctx); _load();
          } catch (_) { debugPrint('创建拜访计划失败'); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('创建失败'), backgroundColor: Colors.red)); }
        }, child: const Text('保存')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拜访计划'), backgroundColor: Colors.blue, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showPlanDialog)]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty ? const Center(child: Text('暂无拜访计划'))
          : RefreshIndicator(onRefresh: _load, child: ListView.builder(
              itemCount: _plans.length,
              itemBuilder: (_, i) {
                final p = _plans[i];
                return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.business, color: Colors.white), backgroundColor: Colors.deepOrange),
                  title: Text(p['content']?.toString().replaceAll('【计划】', '') ?? '拜访'),
                  subtitle: Text(p['address'] ?? p['createdAt'] ?? ''),
                  trailing: Icon(Icons.check_circle_outline, color: p['content']?.toString().contains('计划') == true ? Colors.orange : Colors.green),
                ));
              },
            )),
    );
  }
}

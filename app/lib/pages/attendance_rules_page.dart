import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

class AttendanceRulesPage extends StatefulWidget {
  const AttendanceRulesPage({super.key});
  @override
  State<AttendanceRulesPage> createState() => _AttendanceRulesPageState();
}

class _AttendanceRulesPageState extends State<AttendanceRulesPage> {
  final _auth = AuthService();
  List _rules = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final r = await dio.get('/api/v1/attendance/rules',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _rules = r.data['rules'] ?? []; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: '09:00');
    final endCtrl = TextEditingController(text: '18:00');
    final radiusCtrl = TextEditingController(text: '300');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建打卡规则'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: startCtrl, decoration: const InputDecoration(labelText: '上班时间', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: endCtrl, decoration: const InputDecoration(labelText: '下班时间', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: radiusCtrl, decoration: const InputDecoration(labelText: '有效半径(米)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          if (nameCtrl.text.isEmpty) return;
          try {
            final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            await dio.post('/api/v1/attendance/rules', data: {
              'name': nameCtrl.text, 'startTime': startCtrl.text, 'endTime': endCtrl.text,
              'radius': int.tryParse(radiusCtrl.text) ?? 300,
            }, options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            Navigator.pop(ctx); _load();
          } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e'))); }
        }, child: const Text('创建')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打卡规则'), backgroundColor: Colors.blue, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog)]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty ? const Center(child: Text('暂无打卡规则'))
          : RefreshIndicator(onRefresh: _load, child: ListView.builder(
              itemCount: _rules.length,
              itemBuilder: (_, i) {
                final r = _rules[i];
                return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                  title: Text(r['name'] ?? '未命名'),
                  subtitle: Text('${r['startTime'] ?? "09:00"} - ${r['endTime'] ?? "18:00"} | 半径${r['radius'] ?? 300}m'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      try {
                        final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
                        await dio.delete('/api/v1/attendance/rules/${r['id']}',
                          options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
                        _load();
                      } catch (_) {}
                    }),
                ));
              },
            )),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import 'package:field_tracker/services/amap_location_service.dart';

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
    } catch (e) { debugPrint('加载打卡规则失败: $e'); if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e'))); } }
  }

  /// 根据 rule 预填数据创建/编辑对话框
  void _showRuleDialog({Map? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final startCtrl = TextEditingController(text: existing != null ? (existing['checkin_start']?.toString() ?? '09:00').substring(0,5) : '09:00');
    final endCtrl = TextEditingController(text: existing != null ? (existing['checkin_end']?.toString() ?? '18:00').substring(0,5) : '18:00');
    final radiusCtrl = TextEditingController(text: (existing?['radius_meters'] ?? 300).toString());
    final latCtrl = TextEditingController(text: existing?['center_lat']?.toString() ?? '');
    final lngCtrl = TextEditingController(text: existing?['center_lng']?.toString() ?? '');
    final isEdit = existing != null;

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(isEdit ? '编辑打卡规则' : '新建打卡规则'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: startCtrl, decoration: const InputDecoration(labelText: '上班时间(如 09:00)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: endCtrl, decoration: const InputDecoration(labelText: '下班时间(如 18:00)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: radiusCtrl, decoration: const InputDecoration(labelText: '有效半径(米)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        TextField(controller: latCtrl, decoration: const InputDecoration(labelText: '中心纬度', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 8),
        TextField(controller: lngCtrl, decoration: const InputDecoration(labelText: '中心经度', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            final loc = AmapLocationService();
            final lat = loc.currentLat;
            final lng = loc.currentLng;
            if (lat != null && lng != null) {
              latCtrl.text = lat.toStringAsFixed(6);
              lngCtrl.text = lng.toStringAsFixed(6);
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('尚未获取到位置，请在地图页等待定位'), backgroundColor: Colors.orange));
            }
          },
          icon: const Icon(Icons.my_location, size: 16),
          label: const Text('使用当前位置'),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          if (nameCtrl.text.isEmpty) return;
          final lat = double.tryParse(latCtrl.text);
          final lng = double.tryParse(lngCtrl.text);

          final body = {
            'name': nameCtrl.text,
            'center_lat': lat,
            'center_lng': lng,
            'radius_meters': int.tryParse(radiusCtrl.text) ?? 300,
            'checkin_start': startCtrl.text,
            'checkin_end': endCtrl.text,
            'rule_type': 'location',
          };

          try {
            final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            if (isEdit) {
              await dio.put('/api/v1/attendance/rules/${existing['id']}',
                data: body,
                options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            } else {
              await dio.post('/api/v1/attendance/rules',
                data: body,
                options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx); _load();
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('${isEdit ? "编辑" : "创建"}失败: $e')));
          }
        }, child: Text(isEdit ? '保存' : '创建')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打卡规则'), backgroundColor: Colors.blue, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showRuleDialog())]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty ? const Center(child: Text('暂无打卡规则'))
          : RefreshIndicator(onRefresh: _load, child: ListView.builder(
              itemCount: _rules.length,
              itemBuilder: (_, i) {
                final r = _rules[i];
                return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                  title: Text(r['name'] ?? '未命名'),
                  subtitle: Text(
                    '${(r['checkin_start']?.toString() ?? '不限').substring(0,5)} - ${(r['checkin_end']?.toString() ?? '不限').substring(0,5)} | 半径${r['radius_meters'] ?? 300}m'
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showRuleDialog(existing: r)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        try {
                          final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
                          await dio.delete('/api/v1/attendance/rules/${r['id']}',
                            options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
                          if (!context.mounted) return;
                          _load();
                        } catch (_) { debugPrint('删除打卡规则失败'); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red)); }
                      }),
                  ]),
                ));
              },
            )),
    );
  }
}

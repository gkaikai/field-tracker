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
  List _customers = [];
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
    // 加载客户列表供选择
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final r = await dio.get('/api/v1/customers',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _customers = (r.data['customers'] as List?) ?? []; });
    } catch (_) {}
  }

  void _showPlanDialog() {
    final customerCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateTime.now().toString().substring(0, 10));
    String? selectedCustomerId;
    String selectedCustomerName = '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('新增拜访计划'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Autocomplete<Map>(
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return _customers.cast<Map>();
            return _customers.where((c) =>
              (c['name'] as String).toLowerCase().contains(textEditingValue.text.toLowerCase())
            ).cast<Map>();
          },
          displayStringForOption: (option) => option['name'] ?? '',
          onSelected: (option) {
            selectedCustomerId = option['id'];
            selectedCustomerName = option['name'] ?? '';
            customerCtrl.text = option['name'] ?? '';
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
            TextField(controller: controller, focusNode: focusNode,
              decoration: const InputDecoration(labelText: '选择客户', border: OutlineInputBorder(), hintText: '搜索客户名称'),
              onChanged: (v) { customerCtrl.text = v; }),
        ),
        const SizedBox(height: 8),
        TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: '计划内容', border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 8),
        TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: '计划日期', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          if (customerCtrl.text.isEmpty) return;
          if (selectedCustomerId == null) { messenger.showSnackBar(const SnackBar(content: Text('请从列表中选择客户'), backgroundColor: Colors.orange)); return; }
          try {
            final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            await dio.post('/api/v1/customers/visit', data: {
              'customerId': selectedCustomerId,
              'content': '【计划】${contentCtrl.text}',
              'address': '计划拜访: $selectedCustomerName',
            }, options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            if (!ctx.mounted) return;
            Navigator.pop(ctx); _load();
          } catch (e) {
            debugPrint('创建拜访计划失败: $e');
            messenger.showSnackBar(const SnackBar(content: Text('创建失败'), backgroundColor: Colors.red));
          }
        }, child: const Text('保存')),
      ],
    )));
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
                  leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.business, color: Colors.white)),
                  title: Text(p['content']?.toString().replaceAll('【计划】', '') ?? '拜访'),
                  subtitle: Text(p['address'] ?? p['createdAt'] ?? ''),
                  trailing: Icon(Icons.check_circle_outline, color: p['content']?.toString().contains('计划') == true ? Colors.orange : Colors.green),
                ));
              },
            )),
    );
  }
}

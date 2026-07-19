import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

class ApprovalPage extends StatefulWidget {
  const ApprovalPage({super.key});
  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  final _auth = AuthService();
  List _list = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final r = await dio.get('/api/v1/approvals${_filter == 'all' ? '' : '?status=$_filter'}',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      setState(() { _list = r.data['approvals'] ?? []; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  void _showCreateDialog() {
    String selectedType = 'leave';
    final titleCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: DateTime.now().toString().substring(0, 10));
    final endCtrl = TextEditingController(text: DateTime.now().toString().substring(0, 10));
    bool showAmount = false;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('新建审批'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: selectedType,
          decoration: const InputDecoration(labelText: '类型'),
          items: const [
            DropdownMenuItem(value: 'leave', child: Row(children: [Icon(Icons.event_busy, size: 18), SizedBox(width: 8), Text('请假')])),
            DropdownMenuItem(value: 'business_trip', child: Row(children: [Icon(Icons.flight_takeoff, size: 18), SizedBox(width: 8), Text('出差')])),
            DropdownMenuItem(value: 'expense', child: Row(children: [Icon(Icons.receipt, size: 18), SizedBox(width: 8), Text('报销')])),
          ], onChanged: (v) {
            setDialogState(() { selectedType = v ?? 'leave'; showAmount = v == 'expense'; });
          }),
        const SizedBox(height: 8),
        TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: '原因说明', border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 8),
        if (showAmount)
          TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: '金额(元)', prefixText: '¥ ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        if (!showAmount) ...[
          TextField(controller: startCtrl, decoration: const InputDecoration(labelText: '开始日期', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: endCtrl, decoration: const InputDecoration(labelText: '结束日期', border: OutlineInputBorder())),
        ],
        const SizedBox(height: 8),
        TextField(controller: remarkCtrl, decoration: const InputDecoration(labelText: '备注(可选)', border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          try {
            final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            await dio.post('/api/v1/approvals', data: {
              'type': selectedType, 'title': titleCtrl.text, 'reason': reasonCtrl.text,
              'startDate': startCtrl.text, 'endDate': endCtrl.text, 'duration': '1天',
              if (showAmount) 'amount': amountCtrl.text,
              'remark': remarkCtrl.text,
            }, options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
            Navigator.pop(ctx); _load();
          } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败: $e'))); }
        }, child: const Text('提交')),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('审批'), backgroundColor: Colors.blue, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog)]),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ChoiceChip(label: const Text('全部'), selected: _filter == 'all', onSelected: (_) => setState(() { _filter = 'all'; _load(); })),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('待审批'), selected: _filter == 'pending', onSelected: (_) => setState(() { _filter = 'pending'; _load(); })),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('已通过'), selected: _filter == 'approved', onSelected: (_) => setState(() { _filter = 'approved'; _load(); })),
        ]),
        const Divider(),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
              : _list.isEmpty ? const Center(child: Text('暂无记录'))
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final a = _list[i];
                    final t = a['type'] ?? '';
                    final typeLabel = t == 'leave' ? '请假' : (t == 'expense' ? '报销' : '出差');
                    final typeIcon = t == 'leave' ? Icons.event_busy : (t == 'expense' ? Icons.receipt : Icons.flight_takeoff);
                    final statusColor = a['status'] == 'approved' ? Colors.green : (a['status'] == 'rejected' ? Colors.red : Colors.orange);
                    final amount = a['amount'];
                    final remark = a['remark'] ?? '';
                    String subtitle = a['reason'] ?? '';
                    if (amount != null && amount > 0) subtitle += ' | ¥${amount}';
                    if (remark.isNotEmpty) subtitle += ' | $remark';

                    return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                      leading: Icon(typeIcon, color: Colors.blue),
                      title: Text(a['title'] ?? typeLabel),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Chip(label: Text(a['status'] ?? '待审批', style: const TextStyle(fontSize: 12, color: Colors.white)),
                        backgroundColor: statusColor),
                    ));
                  },
                )),
        ),
      ]),
    );
  }
}

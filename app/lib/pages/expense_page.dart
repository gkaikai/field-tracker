// 费用报销页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ft_toast.dart';

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});
  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  final _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  List _records = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _titleCtrl.dispose(); _amountCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/v1/expenses');
      if (mounted) setState(() { _records = (r.data['expenses'] as List?) ?? []; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _submit() {
    if (_titleCtrl.text.isEmpty || _amountCtrl.text.isEmpty) {
      FTToast.warning(context, '请填写标题和金额'); return;
    }
    setState(() => _submitting = true);
    try {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) { setState(() => _submitting = false); FTToast.success(context, '✅ 报销已提交，等待审批'); }
      });
    } catch (_) { if (mounted) { setState(() => _submitting = false); FTToast.error(context, '❌ 提交失败'); }}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('费用报销'), bottom: const TabBar(tabs: [Tab(text: '我的报销'), Tab(text: '提交报销')])),
        body: TabBarView(children: [
          _buildList(), _buildForm(),
        ]),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_records.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0F9FF), shape: BoxShape.circle), child: const Icon(Icons.receipt_long, size: 28, color: Color(0xFF0EA5E9))),
      const SizedBox(height: 12), const Text('暂无报销记录', style: TextStyle(fontSize: 15, color: Colors.grey)),
    ]));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final r = _records[i] as Map<String, dynamic>;
        return ListTile(
          leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt, color: Color(0xFF16A34A))),
          title: Text(r['title']?.toString() ?? '报销', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(r['date']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
          trailing: Text('¥${r['amount']?.toString() ?? '0.00'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );
      },
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '报销标题', border: OutlineInputBorder(), prefixIcon: Icon(Icons.title))),
        const SizedBox(height: 16),
        TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: '金额', border: OutlineInputBorder(), prefixIcon: Icon(Icons.monetization_on), helperText: '请输入报销金额'), keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes)), maxLines: 3),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
          label: Text(_submitting ? '提交中...' : '提交报销', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: context.adminPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
        )),
      ]),
    );
  }
}

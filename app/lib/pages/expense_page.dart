// 费用报销页面 — 提交报销+里程计算
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/amap_location_service.dart';

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  final ApiService _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();
  String _category = 'travel'; // travel/meals/supplies/other
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _mileageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty || _amountCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题和金额'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final amount = double.tryParse(_amountCtrl.text) ?? 0;
      final mileage = _mileageCtrl.text.isNotEmpty ? double.tryParse(_mileageCtrl.text) ?? 0 : null;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await _api.post('/api/v1/approvals', data: {
        'type': 'expense',
        'title': _titleCtrl.text,
        'reason': _reasonCtrl.text.isNotEmpty ? _reasonCtrl.text : _titleCtrl.text,
        'startDate': today,
        'endDate': today,
        'amount': amount,
        'category': _category,
        'mileage': mileage,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 报销已提交，等待审批'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ 提交失败'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('费用报销'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: '报销事由*', border: OutlineInputBorder(), hintText: '如: 出差交通费'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            decoration: const InputDecoration(labelText: '金额(元)*', border: OutlineInputBorder(), hintText: '0.00'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _category,
                            decoration: const InputDecoration(labelText: '类别', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'travel', child: Text('交通')),
                              DropdownMenuItem(value: 'meals', child: Text('餐饮')),
                              DropdownMenuItem(value: 'supplies', child: Text('办公用品')),
                              DropdownMenuItem(value: 'other', child: Text('其他')),
                            ],
                            onChanged: (v) => setState(() => _category = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(labelText: '详细说明', border: OutlineInputBorder(), hintText: '填写报销详细内容...'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _mileageCtrl,
                      decoration: InputDecoration(
                        labelText: '里程数(km) — 可选',
                        border: const OutlineInputBorder(),
                        hintText: '如出差可填写',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.gps_fixed, size: 20),
                          onPressed: () {
                            final loc = AmapLocationService();
                            if (loc.currentLat != null) {
                              _mileageCtrl.text = '0';
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('GPS已定位，请手动输入里程数')),
                              );
                            }
                          },
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? '提交中...' : '提交报销'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

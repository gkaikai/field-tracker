// 工作汇报页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/ft_toast.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final ApiService _api = ApiService();
  List<dynamic> _reports = []; String _filterType = 'all';
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadReports(); }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final query = _filterType == 'all' ? '' : '?type=$_filterType';
      final resp = await _api.get('/api/v1/reports$query');
      setState(() { _reports = resp.data['reports'] as List<dynamic>; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _createReport() async {
    final contentCtrl = TextEditingController();
    String selectedType = 'daily';
    await showDialog<Map<String, String>>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('写工作汇报'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('汇报类型', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'daily', label: Text('日报')), ButtonSegment(value: 'weekly', label: Text('周报')), ButtonSegment(value: 'monthly', label: Text('月报')),
            ],
            selected: {selectedType},
            onSelectionChanged: (v) => setS(() => selectedType = v.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: '汇报内容', hintText: '请填写今日工作内容...', border: OutlineInputBorder()), maxLines: 6),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () async {
            try {
              await _api.post('/api/v1/reports', data: {'type': selectedType, 'content': contentCtrl.text});
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) { FTToast.success(context, '✅ 提交成功'); _loadReports(); }
            } catch (_) { if (mounted) FTToast.error(context, '❌ 提交失败'); }
          }, child: const Text('提交')),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('工作汇报'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _createReport)]),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            _filterChip('all', '全部'),
            _filterChip('daily', '日报'),
            _filterChip('weekly', '周报'),
            _filterChip('monthly', '月报'),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0F9FF), shape: BoxShape.circle), child: const Icon(Icons.assignment, size: 28, color: Color(0xFF0EA5E9))),
                      const SizedBox(height: 12), const Text('暂无汇报', style: TextStyle(fontSize: 15, color: Colors.grey)),
                      const SizedBox(height: 12), ElevatedButton.icon(onPressed: _createReport, icon: const Icon(Icons.add), label: const Text('写汇报')),
                    ]))
                  : RefreshIndicator(onRefresh: _loadReports, child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final r = _reports[i] as Map<String, dynamic>;
                        final type = r['type'] as String? ?? 'daily';
                        final typeName = {'daily': '日报', 'weekly': '周报', 'monthly': '月报'}[type] ?? '汇报';
                        return ListTile(
                          leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.description, color: Color(0xFF2563EB))),
                          title: Text('$typeName · ${r['date'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(r['content']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: r['status'] == 'submitted' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                            child: Text(r['status'] == 'submitted' ? '已提交' : '待审', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: r['status'] == 'submitted' ? const Color(0xFF16A34A) : const Color(0xFFF59E0B)))),
                        );
                      },
                    )),
        ),
      ]),
    );
  }

  Widget _filterChip(String value, String label) {
    final active = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() { _filterType = value; _loadReports(); }),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFF6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? const Color(0xFF2563EB) : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: active ? const Color(0xFF2563EB) : Colors.grey.shade600, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

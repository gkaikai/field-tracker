// 工作汇报页面

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final ApiService _api = ApiService();
  List<dynamic> _reports = [];
  String _filterType = 'all';
  bool _loading = true;
  int _total = 0;
  int _dailyCount = 0;
  int _weeklyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final query = _filterType == 'all' ? '' : '?type=$_filterType';
      final resp = await _api.get('/api/v1/reports$query');
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _reports = data['reports'] as List<dynamic>;
        _total = (data['pagination'] as Map?)?['total'] as int? ?? 0;
      });
    } catch (_) { debugPrint('加载汇报列表失败'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('加载汇报列表失败'), backgroundColor: Colors.red)); }
    try {
      final statsResp = await _api.get('/api/v1/reports/stats');
      final s = statsResp.data as Map<String, dynamic>;
      _dailyCount = s['daily'] as int;
      _weeklyCount = s['weekly'] as int;
    } catch (_) { debugPrint('加载汇报统计失败'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('加载汇报统计失败'), backgroundColor: Colors.red)); }
    setState(() => _loading = false);
  }

  Future<void> _createReport() async {
    final contentCtrl = TextEditingController();
    String selectedType = 'daily';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('写工作汇报'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('汇报类型'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'daily', label: Text('日报')),
                    ButtonSegment(value: 'weekly', label: Text('周报')),
                    ButtonSegment(value: 'monthly', label: Text('月报')),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (v) => setDialogState(() => selectedType = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(
                    labelText: '汇报内容', hintText: '请填写今日工作内容...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: contentCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, {'type': selectedType, 'content': contentCtrl.text}),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await _api.post('/api/v1/reports', data: result);
      _loadReports();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('提交成功'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作汇报'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _createReport)],
      ),
      body: Column(
        children: [
          // 统计概览
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(Icons.article, '共 $_total 篇', Colors.blue),
                _statItem(Icons.today, '日报 $_dailyCount', Colors.green),
                _statItem(Icons.date_range, '周报 $_weeklyCount', Colors.orange),
              ],
            ),
          ),
          // 筛选标签
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _filterChip('全部', 'all'),
                const SizedBox(width: 8),
                _filterChip('日报', 'daily'),
                const SizedBox(width: 8),
                _filterChip('周报', 'weekly'),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('暂无汇报', style: TextStyle(color: Colors.grey[500])),
                            const SizedBox(height: 8),
                            FilledButton.icon(onPressed: _createReport, icon: const Icon(Icons.add), label: const Text('写汇报')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _reports.length,
                          itemBuilder: (ctx, i) {
                            final r = _reports[i] as Map<String, dynamic>;
                            final type = r['type'] as String? ?? '';
                            final typeLabel = type == 'daily' ? '日报' : type == 'weekly' ? '周报' : '月报';
                            final typeColor = type == 'daily' ? Colors.green : type == 'weekly' ? Colors.orange : Colors.purple;
                            final date = r['date'] as String? ?? '';
                            return Card(
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: typeColor.withOpacity(0.1),
                                  child: Text(typeLabel[0], style: TextStyle(color: typeColor, fontWeight: FontWeight.bold)),
                                ),
                                title: Text('$typeLabel · $date', style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text((r['content'] as String? ?? '').length > 40
                                    ? '${(r['content'] as String).substring(0, 40)}...'
                                    : (r['content'] as String? ?? '')),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r['content'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.6)),
                                        const SizedBox(height: 8),
                                        Text('提交时间: ${r['createdAt'] as String? ?? ''}',
                                            style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        setState(() => _filterType = value);
        _loadReports();
      },
    );
  }
}

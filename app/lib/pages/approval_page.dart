// 审批页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ApprovalPage extends StatefulWidget {
  const ApprovalPage({super.key});
  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabCtrl;
  List _myRequests = []; List _pendingApprovals = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/v1/approvals');
      if (mounted) setState(() { _myRequests = (r.data['myRequests'] as List?) ?? []; _pendingApprovals = (r.data['pending'] as List?) ?? []; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('审批'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '我发起的'),
            Tab(text: '待审批'),
            Tab(text: '已处理'),
          ],
        ),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabCtrl, children: [
              _buildList(_myRequests),
              _buildList(_pendingApprovals),
              _buildList([]),
            ]),
    );
  }

  Widget _buildList(List items) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0F9FF), shape: BoxShape.circle), child: const Icon(Icons.approval, size: 28, color: Color(0xFF0EA5E9))),
        const SizedBox(height: 12), const Text('暂无数据', style: TextStyle(fontSize: 15, color: Colors.grey)),
      ]));
    }
    return RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final item = items[i] as Map<String, dynamic>;
        final typeIcon = item['type'] == 'leave' ? '🏖️' : '✈️';
        return ListTile(
          leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(typeIcon, style: const TextStyle(fontSize: 20)))),
          title: Text(item['title']?.toString() ?? '申请', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(item['date']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
          trailing: _statusBadge(item['status']?.toString() ?? ''),
        );
      },
    ));
  }

  Widget _statusBadge(String status) {
    final config = {
      'pending': {'label': '审批中', 'bg': const Color(0xFFFEF3C7), 'fg': const Color(0xFFF59E0B)},
      'approved': {'label': '已通过', 'bg': const Color(0xFFDCFCE7), 'fg': const Color(0xFF16A34A)},
      'rejected': {'label': '已拒绝', 'bg': const Color(0xFFFEF2F2), 'fg': const Color(0xFFDC2626)},
    };
    final c = config[status] ?? config['pending']!;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c['bg'] as Color, borderRadius: BorderRadius.circular(6)),
      child: Text(c['label'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c['fg'] as Color)),
    );
  }
}

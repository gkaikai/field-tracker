// 拜访执行页面 — 今日任务列表+签到+报告+签退
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/amap_location_service.dart';
import '../utils/time_utils.dart';

class VisitExecPage extends StatefulWidget {
  const VisitExecPage({super.key});

  @override
  State<VisitExecPage> createState() => _VisitExecPageState();
}

class _VisitExecPageState extends State<VisitExecPage> {
  final ApiService _api = ApiService();
  List _visits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodayVisits();
  }

  Future<void> _loadTodayVisits() async {
    setState(() { _isLoading = true; });
    try {
      final resp = await _api.get('/api/v1/visits/today');
      setState(() {
        _visits = (resp.data['visits'] as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载失败，请下拉重试'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _checkin(String id) async {
    try {
      final loc = AmapLocationService();
      final lat = loc.currentLat ?? 0;
      final lng = loc.currentLng ?? 0;
      await _api.post('/api/v1/visits/$id/checkin', data: {'lat': lat, 'lng': lng, 'address': '现场签到'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 签到成功'), backgroundColor: Colors.green),
        );
        _loadTodayVisits();
      }
    } catch (e) {
      String bizMsg = _extractBizMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ 签到失败: $bizMsg'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _checkout(String id) async {
    try {
      final loc = AmapLocationService();
      final lat = loc.currentLat ?? 0;
      final lng = loc.currentLng ?? 0;
      await _api.post('/api/v1/visits/$id/checkout', data: {'lat': lat, 'lng': lng, 'address': '现场签退'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 签退成功'), backgroundColor: Colors.green),
        );
        _loadTodayVisits();
      }
    } catch (e) {
      String bizMsg = _extractBizMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ 签退失败: $bizMsg'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showReportDialog(Map visit) async {
    final contentCtrl = TextEditingController(text: visit['content'] ?? '');
    final resultCtrl = TextEditingController(text: visit['result'] ?? '');
    final nextCtrl = TextEditingController(text: visit['next_plan'] ?? '');
    int satisfaction = visit['satisfaction'] ?? 3;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('拜访报告 — ${visit['customer_name'] ?? ''}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '拜访内容', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: resultCtrl,
                decoration: const InputDecoration(labelText: '结果/成果', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nextCtrl,
                decoration: const InputDecoration(labelText: '下一步计划', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('满意度: ', style: TextStyle(fontSize: 14)),
                  ...List.generate(5, (i) => IconButton(
                    icon: Icon(
                      i < satisfaction ? Icons.star : Icons.star_border,
                      color: Colors.amber, size: 28,
                    ),
                    onPressed: () => setDlgState(() => satisfaction = i + 1),
                  )),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _api.put('/api/v1/visits/${visit['id']}/report', data: {
                    'content': contentCtrl.text,
                    'result': resultCtrl.text,
                    'nextPlan': nextCtrl.text,
                    'satisfaction': satisfaction,
                  });
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 报告已提交'), backgroundColor: Colors.green),
                  );
                  _loadTodayVisits();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('❌ 提交失败: ${_extractBizMessage(e)}'),
                    backgroundColor: Colors.red,
                  ));
                }
              },
              child: const Text('提交报告'),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'planned': return Colors.orange;
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'planned': return '待执行';
      case 'in_progress': return '进行中';
      case 'completed': return '已完成';
      case 'cancelled': return '已取消';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日拜访'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTodayVisits),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTodayVisits,
              child: _visits.isEmpty
                  ? ListView(children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tour, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('今日无拜访计划', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _visits.length,
                      itemBuilder: (_, i) {
                        final v = _visits[i] as Map<String, dynamic>;
                        final status = v['status'] as String? ?? 'planned';
                        final isPlanned = status == 'planned';
                        final isInProgress = status == 'in_progress';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: _statusColor(status).withAlpha(60)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _statusLabel(status),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _statusColor(status),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (v['customer_name'] != null)
                                      Text(
                                        v['customer_name'],
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                                    const Spacer(),
                                    Wrap(spacing: 4, children: [
                                      if (isPlanned)
                                        _actionChip('签到', Colors.blue, () => _checkin(v['id'])),
                                      if (isInProgress) ...[
                                        _actionChip('报告', Colors.teal, () => _showReportDialog(v)),
                                        _actionChip('签退', Colors.green, () => _checkout(v['id'])),
                                      ],
                                    ]),
                                  ],
                                ),
                                if (v['customer_address'] != null && (v['customer_address'] as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on, size: 14, color: Colors.grey[400]),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            v['customer_address'],
                                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (v['start_time'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '开始: ${formatDateTimeFull(v['start_time'] as String?)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                                    ),
                                  ),
                                if (v['end_time'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '结束: ${formatDateTimeFull(v['end_time'] as String?)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _actionChip(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ),
    );
  }

  /// 从 ApiException 响应中提取友好消息
  String _extractBizMessage(dynamic e) {
    try {
      final resp = (e as dynamic).response;
      if (resp?.data is Map) {
        final data = resp.data as Map;
        final msg = data['message'] as String?;
        if (msg != null && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return '服务异常，请稍后重试';
  }
}

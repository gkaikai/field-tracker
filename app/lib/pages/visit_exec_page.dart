// 拜访执行页 v2
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/amap_location_service.dart';
import '../widgets/ft_toast.dart';

class VisitExecPage extends StatefulWidget {
  const VisitExecPage({super.key});
  @override
  State<VisitExecPage> createState() => _VisitExecPageState();
}

class _VisitExecPageState extends State<VisitExecPage> {
  final _api = ApiService();
  List _visits = []; bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await _api.get('/api/v1/visits/today'); setState(() { _visits = (r.data['visits'] as List?) ?? []; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _checkin(Map<String, dynamic> visit) async {
    final loc = AmapLocationService();
    if (loc.currentLat == null) { FTToast.warning(context, '尚未获取到位置'); return; }
    try {
      await _api.post('/api/v1/visits/${visit['id']}/checkin', data: {'visitId': visit['id'], 'lat': loc.currentLat, 'lng': loc.currentLng});
      if (mounted) { FTToast.success(context, '✅ 签到成功'); _load(); }
    } catch (_) { if (mounted) FTToast.error(context, '❌ 签到失败'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日拜访'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _visits.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF0FDF4), shape: BoxShape.circle), child: const Icon(Icons.tour, size: 28, color: Color(0xFF16A34A))),
                  const SizedBox(height: 12), const Text('今日暂无拜访安排', style: TextStyle(fontSize: 15, color: Colors.grey)),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _visits.map((v) {
                    final vm = v as Map<String, dynamic>;
                    final done = vm['checkedIn'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: done ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                          child: Icon(done ? Icons.check_circle : Icons.business, color: done ? const Color(0xFF16A34A) : const Color(0xFF2563EB))),
                        title: Text(vm['name']?.toString() ?? '客户', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(vm['address']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                        trailing: done
                            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                                child: const Text('已签到', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF16A34A))))
                            : ElevatedButton(onPressed: () => _checkin(vm), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: Size.zero, elevation: 0),
                                child: const Text('签到', style: TextStyle(fontSize: 12))),
                      ),
                    );
                  }).toList(),
                )),
    );
  }
}

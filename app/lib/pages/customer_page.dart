// 客户管理 v2
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/route_guard.dart';
import '../config/app_config.dart';
import '../config/amap_key.dart';
import '../widgets/ft_toast.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});
  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final _api = ApiService();
  List _customers = []; bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!RouteGuard.isAdmin()) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pushReplacementNamed(context, '/home'); }); return; }
    _load();
  }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load({String? keyword}) async {
    setState(() => _loading = true);
    try { final q = <String, dynamic>{}; if (keyword != null && keyword.isNotEmpty) q['keyword'] = keyword;
      final r = await _api.get('/api/v1/customers', query: q);
      setState(() { _customers = ((r.data as Map)['customers'] as List?) ?? []; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _form({Map? existing}) {
    final edit = existing != null;
    final nc = TextEditingController(text: existing?['name'] ?? '');
    final pc = TextEditingController(text: existing?['phone'] ?? '');
    final searchCtrl = TextEditingController(text: existing?['address'] ?? '');
    List<Map<String, dynamic>> suggestions = []; bool showSug = false;
    double selectedLat = (existing?['lat'] as num?)?.toDouble() ?? 0;
    double selectedLng = (existing?['lng'] as num?)?.toDouble() ?? 0;
    Timer? debounce;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text(edit ? '编辑客户' : '添加客户'),
      content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: nc, decoration: const InputDecoration(labelText: '客户名称 *', border: OutlineInputBorder()), autofocus: true),
        const SizedBox(height: 8),
        TextField(controller: pc, decoration: const InputDecoration(labelText: '联系电话', border: OutlineInputBorder(), helperText: '11位手机号'), keyboardType: TextInputType.phone, maxLength: 11),
        const SizedBox(height: 8),
        TextField(controller: searchCtrl, decoration: InputDecoration(labelText: '搜索地址', prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(),
          suffixIcon: searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { searchCtrl.clear(); setS(() { suggestions = []; showSug = false; }); }) : null),
          onChanged: (v) {
            debounce?.cancel();
            if (v.length < 3) { setS(() { showSug = false; suggestions = []; }); return; }
            debounce = Timer(const Duration(milliseconds: 400), () async {
              try {
                final resp = await ApiService.amapDio.get(
                  'https://restapi.amap.com/v3/assistant/inputtips',
                  queryParameters: {'key': AMapConfig.webServiceKey, 'keywords': v.trim(), 'output': 'JSON'},
                );
                final tips = (resp.data['tips'] as List?) ?? [];
                setS(() {
                  suggestions = tips.map((t) {
                    final m = t as Map<String, dynamic>;
                    return <String, dynamic>{
                      'name': (m['name'] ?? '').toString(),
                      'address': (m['address'] ?? '').toString(),
                      'location': (m['location'] ?? '').toString(),
                      'district': (m['district'] ?? '').toString(),
                    };
                  }).toList();
                  showSug = suggestions.isNotEmpty;
                });
              } catch (_) {}
            });
          },
        ),
        if (showSug && suggestions.isNotEmpty) ...[const SizedBox(height: 4),
          Container(height: 150, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: ListView.separated(itemCount: suggestions.length, separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) { final s = suggestions[i]; return ListTile(dense: true,
                title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                subtitle: Text(s['address'] ?? '', style: const TextStyle(fontSize: 11)),
                onTap: () { searchCtrl.text = s['name'] ?? ''; final loc = s['location']?.toString() ?? ''; if (loc.contains(',')) { final parts = loc.split(','); selectedLng = double.tryParse(parts[0]) ?? 0; selectedLat = double.tryParse(parts[1]) ?? 0; } setS(() { showSug = false; }); },
              );},
            ),
          ),
        ],
      ]))),
      actions: [
        if (edit) TextButton(onPressed: () async {
          try { await _api.delete('/api/v1/customers/${existing!['id']}'); if (ctx.mounted) Navigator.pop(ctx); if (mounted) { FTToast.success(context, '已删除'); _load(); } }
          catch (_) { if (mounted) FTToast.error(context, '删除失败'); }
        }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () async {
          final data = {'name': nc.text, 'phone': pc.text, 'lat': selectedLat, 'lng': selectedLng, 'address': searchCtrl.text};
          try {
            if (edit) { await _api.put('/api/v1/customers/${existing!['id']}', data: data); }
            else { await _api.post('/api/v1/customers', data: data); }
            if (ctx.mounted) Navigator.pop(ctx); if (mounted) { FTToast.success(context, edit ? '已更新' : '已添加'); _load(); }
          } catch (_) { if (mounted) FTToast.error(context, '操作失败'); }
        }, child: Text(edit ? '保存' : '添加')),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('客户管理'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _form())]),
      body: Column(children: [
        Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: TextField(
          controller: _searchCtrl, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: '搜索客户名称/地址...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade100),
          onChanged: (v) => _load(keyword: v.isNotEmpty ? v : null),
        )),
        const Divider(height: 16),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
            : _customers.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFFEF3C7), shape: BoxShape.circle), child: const Icon(Icons.business, size: 28, color: Color(0xFFF59E0B))),
                const SizedBox(height: 12), const Text('暂无客户', style: TextStyle(fontSize: 15, color: Colors.grey)),
              ]))
            : RefreshIndicator(onRefresh: () => _load(), child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _customers.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final c = _customers[i] as Map<String, dynamic>;
                  final tags = (c['tags'] as List?)?.cast<String>() ?? [];
                  final visitCount = c['visitCount'] ?? 0;
                  return ListTile(
                    leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.business, color: Color(0xFFF59E0B))),
                    title: Text(c['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('📍 ${c['address'] ?? ""}', style: const TextStyle(fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                        child: Text('$visitCount次拜访', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF2563EB)))),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                    ]),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CustomerDetail(customer: c, api: _api))),
                  );
                },
              )),
        ),
      ]),
    );
  }
}

class _CustomerDetail extends StatelessWidget {
  final Map<String, dynamic> customer;
  final ApiService api;
  const _CustomerDetail({required this.customer, required this.api});

  @override
  Widget build(BuildContext context) {
    final tags = (customer['tags'] as List?)?.cast<String>() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(customer['name']?.toString() ?? '')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.phone, customer['phone']?.toString() ?? '无电话'),
          const Divider(),
          _row(Icons.location_on, customer['address']?.toString() ?? '无地址'),
          const Divider(),
          _row(Icons.tag, tags.isNotEmpty ? tags.join(', ') : '无标签'),
        ]))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () async {
            try {
              await api.post('/api/v1/customers/visit', data: {'customerId': customer['id'], 'content': '拜访客户: ${customer['name']}'});
              if (context.mounted) FTToast.success(context, '✅ 拜访记录成功');
            } catch (_) { if (context.mounted) FTToast.error(context, '❌ 失败'); }
          },
          icon: const Icon(Icons.tour), label: const Text('记录拜访'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
        )),
      ]),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 18, color: Colors.grey.shade600), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 14)))]);
  }
}

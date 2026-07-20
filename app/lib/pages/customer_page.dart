// 客户管理页面
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});
  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final _api = ApiService();
  List _customers = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load({String? keyword}) async {
    setState(() => _loading = true);
    try {
      final q = <String, dynamic>{};
      if (keyword != null && keyword.isNotEmpty) q['keyword'] = keyword;
      final r = await _api.get('/api/v1/customers', query: q);
      setState(() => _customers = ((r.data as Map)['customers'] as List?) ?? []);
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _form({Map? existing}) {
    final edit = existing != null;
    final nc = TextEditingController(text: existing?['name'] ?? '');
    final pc = TextEditingController(text: existing?['phone'] ?? '');
    final ac = TextEditingController(text: existing?['address'] ?? '');
    final lc = TextEditingController(text: (existing?['lat']?.toString() ?? '22.55'));
    final lgc = TextEditingController(text: (existing?['lng']?.toString() ?? '114.08'));
    final rc = TextEditingController(text: existing?['remark'] ?? '');
    final tc = TextEditingController();
    List<String> tags = existing != null ? ((existing['tags'] as List?)?.cast<String>() ?? []) : [];
    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: Text(edit ? '编辑客户' : '添加客户'),
          content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nc, decoration: const InputDecoration(labelText: '客户名称 *', border: OutlineInputBorder()), autofocus: true),
            const SizedBox(height: 8),
            TextField(controller: pc, decoration: const InputDecoration(labelText: '联系电话', border: OutlineInputBorder(), helperText: '支持国际号码'), keyboardType: TextInputType.phone, maxLength: 20),
            const SizedBox(height: 8),
            TextField(controller: ac, decoration: const InputDecoration(labelText: '地址', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: lc, decoration: const InputDecoration(labelText: '纬度', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: lgc, decoration: const InputDecoration(labelText: '经度', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: tc, decoration: const InputDecoration(labelText: '标签', hintText: '回车添加', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (v) { if (v.trim().isNotEmpty) { setS(() { tags.add(v.trim()); tc.clear(); }); } })),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { if (tc.text.trim().isNotEmpty) { setS(() { tags.add(tc.text.trim()); tc.clear(); }); } }),
            ]),
            if (tags.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(height: 30,
              child: ListView(scrollDirection: Axis.horizontal, children: tags.map((t) => Padding(padding: const EdgeInsets.only(right: 4),
                child: Chip(label: Text(t, style: const TextStyle(fontSize: 12)), onDeleted: () => setS(() => tags.remove(t)),
                  deleteIcon: const Icon(Icons.close, size: 14), visualDensity: VisualDensity.compact))).toList()))),
            TextField(controller: rc, decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder()), maxLines: 2),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(onPressed: () async {
              if (nc.text.trim().isEmpty) return;
              final data = {'name': nc.text.trim(), 'phone': pc.text, 'address': ac.text,
                'lat': double.tryParse(lc.text) ?? 0, 'lng': double.tryParse(lgc.text) ?? 0, 'remark': rc.text, 'tags': tags};
              try {
                if (edit) { await _api.put('/api/v1/customers/${existing['id']}', data: data); }
                else { await _api.post('/api/v1/customers', data: data); }
                Navigator.pop(ctx); _load();
              } catch (e) { ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${edit?"编辑":"添加"}失败: $e'))); }
            }, child: Text(edit ? '保存' : '添加')),
          ],
        );
      });
    });
  }

  void _delete(Map c) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除客户'), content: Text('确定删除"${c['name']}"？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.white)),
          style: FilledButton.styleFrom(backgroundColor: Colors.red))],
    ));
    if (ok != true) return;
    try { await _api.delete('/api/v1/customers/${c['id']}'); _load(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已删除'),backgroundColor:Colors.green)); }
    catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('删除失败: $e'),backgroundColor:Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('客户管理'), backgroundColor: Colors.blue, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _form())]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(hintText: '搜索名称/电话...', prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            filled: true, fillColor: Colors.grey[100], contentPadding: const EdgeInsets.symmetric(vertical: 10)),
          onChanged: (v) => _load(keyword: v.isEmpty ? null : v),
        )),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
            : _customers.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(_searchCtrl.text.isNotEmpty ? '未找到匹配客户' : '暂无客户', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                  if (_searchCtrl.text.isEmpty) FilledButton.icon(onPressed: () => _form(), icon: const Icon(Icons.add), label: const Text('添加客户')),
                ]))
              : RefreshIndicator(onRefresh: () => _load(keyword: _searchCtrl.text.isEmpty ? null : _searchCtrl.text),
                  child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _customers.length, itemBuilder: (_, i) {
                    final c = _customers[i] as Map;
                    final tags = (c['tags'] as List?)?.cast<String>() ?? [];
                    return Card(child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.green[50], child: const Icon(Icons.business, color: Colors.green)),
                      title: Text(c['name'] ?? ''), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((c['phone'] ?? '').isNotEmpty) Text('📞 ${c['phone']}', style: const TextStyle(fontSize: 13)),
                        if ((c['address'] ?? '').isNotEmpty) Text('📍 ${c['address']}', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Wrap(spacing: 4,
                          children: tags.take(3).map((t) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                            child: Text(t, style: TextStyle(fontSize: 10, color: Colors.blue[700])))).toList())),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue), constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _form(existing: c)),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _delete(c)),
                        const Icon(Icons.chevron_right, size: 20),
                      ]),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CustomerDetail(customer: c, onUpdate: _load))),
                    ));
                  }),
                ),
        ),
      ]),
    );
  }
}

class _CustomerDetail extends StatefulWidget {
  final Map customer;
  final VoidCallback onUpdate;
  const _CustomerDetail({required this.customer, required this.onUpdate});
  @override
  State<_CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends State<_CustomerDetail> {
  final _api = ApiService();
  List _visits = [];

  @override
  void initState() { super.initState(); _loadVisits(); }

  Future<void> _loadVisits() async {
    try {
      final r = await _api.get('/api/v1/customers/visits', query: {'customerId': '${widget.customer['id']}'});
      setState(() => _visits = ((r.data as Map)['visits'] as List?) ?? []);
    } catch (_) {}
  }

  void _addVisit() async {
    final cc = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('记录拜访'),
      content: TextField(controller: cc, decoration: const InputDecoration(labelText: '拜访内容', hintText: '描述...', border: OutlineInputBorder()), maxLines: 3),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: cc.text.trim().isEmpty ? null : () => Navigator.pop(ctx, cc.text), child: const Text('提交'))],
    ));
    if (text == null) return;
    try {
      await _api.post('/api/v1/customers/visit', data: {
        'customerId': widget.customer['id'], 'content': text,
        'lat': widget.customer['lat'] ?? 0, 'lng': widget.customer['lng'] ?? 0,
      });
      _loadVisits();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拜访记录成功'), backgroundColor: Colors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final tags = (c['tags'] as List?)?.cast<String>() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(c['name'] ?? ''), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.phone, c['phone'] ?? '无电话'),
          const SizedBox(height: 8), _row(Icons.location_on, c['address'] ?? '无地址'),
          const SizedBox(height: 8), _row(Icons.map, '${((c['lat'] as num?) ?? 0).toStringAsFixed(4)}, ${((c['lng'] as num?) ?? 0).toStringAsFixed(4)}'),
          if (tags.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 4, runSpacing: 4,
            children: tags.map((t) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
              child: Text(t, style: TextStyle(fontSize: 12, color: Colors.blue[700])))).toList())],
          if ((c['remark'] ?? '').isNotEmpty) ...[const SizedBox(height: 8), _row(Icons.notes, c['remark'])],
        ]))),
        const SizedBox(height: 12),
        Row(children: [const Text('拜访记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(),
          FilledButton.icon(onPressed: _addVisit, icon: const Icon(Icons.add, size: 18), label: const Text('记录拜访'))]),
        const SizedBox(height: 8),
        if (_visits.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('暂无拜访记录', style: TextStyle(color: Colors.grey[500])))))
        else ...buildVisitCards(),
      ]),
    );
  }

  List<Widget> buildVisitCards() {
    final cards = <Widget>[];
    for (final v in _visits) {
      final vm = v as Map;
      final photos = (vm['photos'] as List?)?.cast<String>() ?? [];
      cards.add(Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: Colors.orange[50], radius: 16, child: const Icon(Icons.assignment, color: Colors.orange, size: 18)),
          const SizedBox(width: 8), Expanded(child: Text(vm['content'] ?? '', style: const TextStyle(fontSize: 14))),
        ]),
        const SizedBox(height: 4),
        Text(vm['createdAt'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]))));
      if (photos.isNotEmpty) {
        cards.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(height: 80,
          child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: photos.length,
            itemBuilder: (_, pi) => Padding(padding: const EdgeInsets.only(right: 4),
              child: ClipRRect(borderRadius: BorderRadius.circular(4),
                child: Image.network('${AppConfig.baseUrl}${photos[pi]}', width: 80, height: 80, fit: BoxFit.cover)))))));
      }
    }
    return cards;
  }

  Widget _row(IconData icon, String text) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 6), Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
    ]);
  }
}

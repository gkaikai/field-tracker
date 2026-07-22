// 客户管理页面
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';
import '../config/amap_key.dart';

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

  /// 添加/编辑客户表单（地址搜索代替手动填经纬度）
  void _form({Map? existing}) {
    final edit = existing != null;
    final nc = TextEditingController(text: existing?['name'] ?? '');
    final pc = TextEditingController(text: existing?['phone'] ?? '');
    final ac = TextEditingController(text: existing?['address'] ?? '');
    // 搜索相关
    final searchCtrl = TextEditingController(text: existing?['address'] ?? '');
    List<Map<String, dynamic>> suggestions = [];
    bool showSug = false;
    // 隐藏的经纬度（搜索选择后自动填充）
    double selectedLat = (existing?['lat'] as num?)?.toDouble() ?? 0;
    double selectedLng = (existing?['lng'] as num?)?.toDouble() ?? 0;
    Timer? debounce;

    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: Text(edit ? '编辑客户' : '添加客户'),
          content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: nc, decoration: const InputDecoration(labelText: '客户名称 *', border: OutlineInputBorder()), autofocus: true),
            const SizedBox(height: 8),
            TextField(controller: pc, decoration: const InputDecoration(labelText: '联系电话', border: OutlineInputBorder(), helperText: '11位手机号'), keyboardType: TextInputType.phone, maxLength: 11),
            const SizedBox(height: 8),
            // 地址搜索框（替代原来的地址+经纬度手填）
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                labelText: '搜索地址',
                hintText: '输入地址关键词搜索...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          searchCtrl.clear();
                          setS(() {
                            showSug = false;
                            suggestions = [];
                            selectedLat = 0;
                            selectedLng = 0;
                            ac.text = '';
                          });
                        })
                    : null,
              ),
              onChanged: (v) {
                ac.text = v;
                debounce?.cancel();
                if (v.trim().isEmpty) {
                  setS(() { showSug = false; suggestions = []; });
                  return;
                }
                debounce = Timer(const Duration(milliseconds: 400), () async {
                  try {
                    final dio = Dio();
                    final resp = await dio.get(
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
            // 地址建议下拉列表
            if (showSug && suggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: suggestions.length > 8 ? 8 : suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = suggestions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on, size: 18, color: Colors.grey),
                      title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: s['address']?.isNotEmpty == true
                          ? Text('${s['address']}', style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () {
                        final locStr = s['location'] ?? '';
                        if (locStr.contains(',')) {
                          final parts = locStr.split(',');
                          selectedLng = double.tryParse(parts[0]) ?? 0;
                          selectedLat = double.tryParse(parts[1]) ?? 0;
                        }
                        final addr = s['name'] ?? '';
                        final district = s['district'] ?? '';
                        final fullAddr = [district, addr].where((x) => x.isNotEmpty).join('');
                        searchCtrl.text = fullAddr;
                        ac.text = fullAddr;
                        setS(() { showSug = false; suggestions = []; });
                      },
                    );
                  },
                ),
              ),
            // 显示已选中的位置信息（只读，不可手动编辑）
            if (selectedLat != 0 || selectedLng != 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text('已定位: ${selectedLat.toStringAsFixed(4)}, ${selectedLng.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ),
            const SizedBox(height: 8),
            // 标签输入
            _TagsInput(existing: existing, onTagsChanged: (tags) {}),
            const SizedBox(height: 8),
            TextField(controller: ac, decoration: const InputDecoration(labelText: '地址', border: OutlineInputBorder(), helperText: '由地址搜索自动填入，可手动修改'), maxLines: 2),
            const SizedBox(height: 8),
            // 备注
            TextField(controller: TextEditingController(text: existing?['remark'] ?? ''),
              decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder()), maxLines: 2),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(onPressed: () async {
              if (nc.text.trim().isEmpty) return;
              // 手机号校验
              final phone = pc.text.trim();
              if (phone.isNotEmpty) {
                final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
                // 支持5~20位数字（国际号码格式）
                if (phone.length != digitsOnly.length || digitsOnly.length < 5 || digitsOnly.length > 20) {
                  if (ctx.mounted) {
                    showDialog(context: ctx, builder: (dCtx) => AlertDialog(
                      title: const Text('提示'),
                      content: const Text('手机号格式不正确（请输入5~20位数字，支持国际号码）'),
                      actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('确定'))],
                    ));
                  }
                  return;
                }
              }
              final remarkCtrl = TextEditingController(text: existing?['remark'] ?? '');
              final data = {
                'name': nc.text.trim(),
                'phone': pc.text,
                'address': ac.text,
                'lat': selectedLat,
                'lng': selectedLng,
                'remark': remarkCtrl.text,
              };
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

// ============================================================
//  标签输入组件
// ============================================================
class _TagsInput extends StatefulWidget {
  final Map? existing;
  final Function(List<String>) onTagsChanged;
  const _TagsInput({this.existing, required this.onTagsChanged});
  @override
  State<_TagsInput> createState() => _TagsInputState();
}

class _TagsInputState extends State<_TagsInput> {
  late List<String> _tags;
  final _tc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = widget.existing != null
        ? ((widget.existing!['tags'] as List?)?.cast<String>() ?? [])
        : [];
  }

  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _tc, decoration: const InputDecoration(labelText: '标签', hintText: '回车添加', isDense: true, border: OutlineInputBorder()),
          onSubmitted: (v) { if (v.trim().isNotEmpty) { setState(() { _tags.add(v.trim()); _tc.clear(); widget.onTagsChanged(_tags); }); } })),
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { if (_tc.text.trim().isNotEmpty) { setState(() { _tags.add(_tc.text.trim()); _tc.clear(); widget.onTagsChanged(_tags); }); } }),
      ]),
      if (_tags.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: SizedBox(height: 30,
          child: ListView(scrollDirection: Axis.horizontal, children: _tags.map((t) => Padding(padding: const EdgeInsets.only(right: 4),
            child: Chip(label: Text(t, style: const TextStyle(fontSize: 12)), onDeleted: () => setState(() { _tags.remove(t); widget.onTagsChanged(_tags); }),
              deleteIcon: const Icon(Icons.close, size: 14), visualDensity: VisualDensity.compact))).toList()))),
    ]);
  }
}

// ============================================================
//  客户详情页
// ============================================================
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
    bool canSubmit = false;
    final text = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('记录拜访'),
        content: TextField(
          controller: cc,
          decoration: const InputDecoration(labelText: '拜访内容', hintText: '描述...', border: OutlineInputBorder()),
          maxLines: 3,
          onChanged: (v) => setS(() => canSubmit = v.trim().isNotEmpty),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: canSubmit ? () => Navigator.pop(ctx, cc.text) : null,
            child: const Text('提交'),
          ),
        ],
      );
    }));
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

// 员工管理页 v2
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/route_guard.dart';
import '../../services/auth_service.dart';
import '../../services/app_role.dart';
import '../../widgets/ft_toast.dart';
import '../../theme/app_theme.dart';

class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({super.key});
  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  final _api = ApiService(); final _auth = AuthService();
  List _users = []; bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); if (!RouteGuard.isAdmin()) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pushReplacementNamed(context, '/home'); }); return; } _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await _api.get('/api/v1/users'); setState(() { _users = (r.data['users'] as List?) ?? []; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Color _roleColor(String? role) {
    switch (role) { case 'admin': return const Color(0xFF7C3AED); case 'manager': return const Color(0xFFF59E0B); default: return const Color(0xFF2563EB); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('员工管理'),
        backgroundColor: context.adminPrimary,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showForm)]),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(12), child: TextField(
          controller: _searchCtrl, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: '搜索员工姓名/工号...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade100),
          onChanged: (_) => setState(() {}),
        )),
        const Divider(height: 1),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final u = _users[i] as Map<String, dynamic>;
                    final name = u['name']?.toString() ?? '';
                    final role = u['role']?.toString() ?? 'employee';
                    final online = u['online'] == true;
                    return ListTile(
                      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: _roleColor(role).withOpacity(0.1), shape: BoxShape.circle),
                        child: Center(child: Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _roleColor(role))))),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${u['code'] ?? ''} · ${u['department'] ?? ''} · ${AppRole.label(role)}', style: const TextStyle(fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: online ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                          child: Text(online ? '在线' : '离线', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: online ? const Color(0xFF16A34A) : Colors.grey.shade500))),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                      ]),
                      onTap: () => _showForm(user: u),
                    );
                  },
                )),
        ),
      ]),
    );
  }

  void _showForm({Map? user}) {
    final edit = user != null;
    final nameCtrl = TextEditingController(text: user?['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: user?['phone']?.toString() ?? '');
    String selectedRole = user?['role']?.toString() ?? 'employee';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text(edit ? '编辑员工' : '添加员工'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '手机号', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField(value: selectedRole, items: AppRole.allOptions.map((o) => DropdownMenuItem(value: o['value'], child: Text(o['label']!))).toList(),
          onChanged: (v) => setS(() => selectedRole = v ?? 'employee'), decoration: const InputDecoration(labelText: '角色', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        if (edit) TextButton(onPressed: () async {
          try { await _api.delete('/api/v1/users/${user!['id']}'); if (ctx.mounted) Navigator.pop(ctx); if (mounted) { FTToast.success(context, '已停用'); _load(); } }
          catch (_) { if (mounted) FTToast.error(context, '停用失败'); }
        }, child: const Text('停用', style: TextStyle(color: Colors.red))),
        ElevatedButton(onPressed: () async {
          try {
            if (edit) { await _api.put('/api/v1/users/${user!['id']}', data: {'name': nameCtrl.text, 'phone': phoneCtrl.text, 'role': selectedRole}); }
            else { await _api.post('/api/v1/users', data: {'name': nameCtrl.text, 'phone': phoneCtrl.text, 'role': selectedRole}); }
            if (ctx.mounted) Navigator.pop(ctx); if (mounted) { FTToast.success(context, edit ? '更新成功' : '添加成功'); _load(); }
          } catch (_) { if (mounted) FTToast.error(context, '操作失败'); }
        }, child: Text(edit ? '保存' : '添加')),
      ],
    )));
  }
}

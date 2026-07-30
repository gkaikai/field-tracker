/// 员工管理页面 — 管理员可在APP上管理员工账号
library;
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/error_codes.dart';
import '../../services/route_guard.dart';
class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _departments = [];
  bool _loading = true;
  String _search = '';
  String? _filterRole;
  String? _filterDept;

  @override
  void initState() {
    super.initState();
    if (!RouteGuard.isAdmin()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      });
      return;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/api/v1/org/users'),
        _api.get('/api/v1/org/departments'),
      ]);
      final users = (results[0].data as List).cast<Map<String, dynamic>>();
      final depts = (results[1].data as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _users = users;
        _departments = depts;
        _filtered = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载失败'), backgroundColor: Colors.red),
      );
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _users.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final phone = (u['phone'] ?? '').toString();
        final role = (u['role'] ?? 'employee').toString();
        final dept = (u['departmentId'] ?? '').toString();
        if (_search.isNotEmpty &&
            !name.contains(_search.toLowerCase()) &&
            !phone.contains(_search)) return false;
        if (_filterRole != null && role != _filterRole) return false;
        if (_filterDept != null && dept != _filterDept) return false;
        return true;
      }).toList();
    });
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: '123456');
    String role = 'employee';
    String? deptId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加员工'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '手机号', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextField(controller: passwordCtrl, decoration: const InputDecoration(labelText: '密码（默认123456）', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: '角色', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'employee', child: Text('员工')),
                  DropdownMenuItem(value: 'admin', child: Text('管理员')),
                  DropdownMenuItem(value: 'manager', child: Text('经理')),
                ],
                onChanged: (v) => role = v ?? 'employee',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: deptId,
                decoration: const InputDecoration(labelText: '部门', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无部门')),
                  ..._departments.map((d) => DropdownMenuItem(
                    value: d['id'].toString(),
                    child: Text(d['name'] ?? ''),
                  )),
                ],
                onChanged: (v) => deptId = v,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _createUser({
                'name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'password': passwordCtrl.text.trim(),
                'role': role,
                'departmentId': deptId,
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser(Map<String, dynamic> data) async {
    try {
      await _api.post('/api/v1/org/users', data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('员工添加成功'), backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      String msg = '添加失败';
      if (e is ApiException) {
        msg = e.friendlyMessage;
        if (e.code == 409) msg = '该手机号已被注册';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final nameCtrl = TextEditingController(text: user['name'] ?? '');
    String role = user['role'] ?? 'employee';
    String? deptId = user['departmentId']?.toString();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${user['name'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Text('手机号: ${user['phone'] ?? ''}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: '角色', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'employee', child: Text('员工')),
                  DropdownMenuItem(value: 'admin', child: Text('管理员')),
                  DropdownMenuItem(value: 'manager', child: Text('经理')),
                ],
                onChanged: (v) => role = v ?? 'employee',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: deptId,
                decoration: const InputDecoration(labelText: '部门', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无部门')),
                  ..._departments.map((d) => DropdownMenuItem(
                    value: d['id'].toString(),
                    child: Text(d['name'] ?? ''),
                  )),
                ],
                onChanged: (v) => deptId = v,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _updateUser(user['id'].toString(), {
                'name': nameCtrl.text.trim(),
                'role': role,
                'departmentId': deptId,
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUser(String id, Map<String, dynamic> data) async {
    try {
      await _api.put('/api/v1/org/users/$id', data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新成功'), backgroundColor: Colors.green),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新失败'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _disableUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认停用'),
        content: Text('确定要停用 ${user['name'] ?? ''} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('停用'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete('/api/v1/org/users/${user['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['name']} 已停用'), backgroundColor: Colors.orange),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('停用失败'), backgroundColor: Colors.red),
      );
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin': return Colors.indigo;
      case 'manager': return Colors.teal;
      default: return Colors.green;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin': return '管理员';
      case 'manager': return '经理';
      default: return '员工';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('员工管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加员工',
            onPressed: _showAddDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索+筛选栏
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '搜索姓名/手机号',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (v) {
                    _search = v;
                    _applyFilter();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _filterRole,
                        decoration: const InputDecoration(
                          labelText: '角色',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('全部角色')),
                          const DropdownMenuItem(value: 'employee', child: Text('员工')),
                          const DropdownMenuItem(value: 'admin', child: Text('管理员')),
                          const DropdownMenuItem(value: 'manager', child: Text('经理')),
                        ],
                        onChanged: (v) {
                          _filterRole = v;
                          _applyFilter();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _filterDept,
                        decoration: const InputDecoration(
                          labelText: '部门',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('全部部门')),
                          ..._departments.map((d) => DropdownMenuItem(
                            value: d['id'].toString(),
                            child: Text(d['name'] ?? '', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) {
                          _filterDept = v;
                          _applyFilter();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 统计栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('共 ${_filtered.length} 人', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const Spacer(),
                Text('${_users.length} 总员工', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ],
            ),
          ),

          // 员工列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('暂无员工', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final u = _filtered[i];
                            final role = (u['role'] ?? 'employee').toString();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _roleColor(role).withOpacity(0.15),
                                child: Text(
                                  ((u['name'] ?? '?').toString().isNotEmpty ? u['name'][0] : '?'),
                                  style: TextStyle(color: _roleColor(role), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _roleColor(role).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _roleColor(role).withOpacity(0.3)),
                                    ),
                                    child: Text(_roleLabel(role),
                                        style: TextStyle(fontSize: 11, color: _roleColor(role))),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${u['phone'] ?? ''}  ${u['department'] ?? ''}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _showEditDialog(u);
                                  if (v == 'disable') _disableUser(u);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Row(
                                    children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('编辑')],
                                  )),
                                  const PopupMenuItem(value: 'disable', child: Row(
                                    children: [Icon(Icons.block, size: 18, color: Colors.red), SizedBox(width: 8), Text('停用', style: TextStyle(color: Colors.red))],
                                  )),
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
}

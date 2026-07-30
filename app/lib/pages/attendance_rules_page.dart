// 打卡规则页 v3 — 可编辑/可新建/可删除
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../../theme/app_theme.dart';
class AttendanceRulesPage extends StatefulWidget {
  const AttendanceRulesPage({super.key});
  @override
  State<AttendanceRulesPage> createState() => _AttendanceRulesPageState();
}

class _AttendanceRulesPageState extends State<AttendanceRulesPage> {
  final _api = ApiService();
  List _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/v1/attendance/rules');
      setState(() {
        _rules = (r.data['rules'] as List?) ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡规则'),
        backgroundColor: context.adminPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0F9FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.checklist, size: 28, color: Color(0xFF0EA5E9)),
                      ),
                      const SizedBox(height: 12),
                      const Text('暂无打卡规则', style: TextStyle(fontSize: 15, color: Colors.grey)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showEditDialog(null),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建规则'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _rules.map((r) {
                      final rm = r as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showEditDialog(rm),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        rm['name']?.toString() ?? '规则',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '生效',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF16A34A)),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                      onSelected: (v) {
                                        if (v == 'edit') _showEditDialog(rm);
                                        if (v == 'delete') _confirmDelete(rm);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _row('⏰', '上班', '${rm['startTime'] ?? '09:00'} - ${rm['lateTime'] ?? '09:30'}'),
                                _row('⏰', '下班', '${rm['endTime'] ?? '18:00'}'),
                                _row('📍', '方式', '位置 + WiFi'),
                                _row('📏', '范围', '${rm['radius'] ?? 100}m'),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
    );
  }

  Widget _row(String icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic>? rule) {
    final isEdit = rule != null;
    final nameCtrl = TextEditingController(text: rule?['name']?.toString() ?? '');
    final startCtrl = TextEditingController(text: rule?['startTime']?.toString() ?? '09:00');
    final lateCtrl = TextEditingController(text: rule?['lateTime']?.toString() ?? '09:30');
    final endCtrl = TextEditingController(text: rule?['endTime']?.toString() ?? '18:00');
    final radiusCtrl = TextEditingController(text: (rule?['radius'] ?? 100).toString());
    _saving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(isEdit ? '编辑规则' : '新建规则'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '规则名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: const InputDecoration(
                            labelText: '上班时间',
                            hintText: '09:00',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lateCtrl,
                          decoration: const InputDecoration(
                            labelText: '迟到时间',
                            hintText: '09:30',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: const InputDecoration(
                            labelText: '下班时间',
                            hintText: '18:00',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: radiusCtrl,
                          decoration: const InputDecoration(
                            labelText: '范围(米)',
                            hintText: '100',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('请输入规则名称')),
                          );
                          return;
                        }
                        setDialogState(() => _saving = true);
                        try {
                          final data = {
                            'name': name,
                            'startTime': startCtrl.text.trim(),
                            'lateTime': lateCtrl.text.trim(),
                            'endTime': endCtrl.text.trim(),
                            'radius': int.tryParse(radiusCtrl.text.trim()) ?? 100,
                          };
                          if (isEdit) {
                            await _api.put('/api/v1/attendance/rules/${rule['id']}', data: data);
                          } else {
                            await _api.post('/api/v1/attendance/rules', data: data);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          _load();
                        } catch (e) {
                          setDialogState(() => _saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(isEdit ? '更新失败' : '创建失败'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? '保存' : '创建'),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _saving = false;

  void _confirmDelete(Map<String, dynamic> rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定要删除「${rule['name'] ?? ''}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _api.delete('/api/v1/attendance/rules/${rule['id']}');
                _load();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// 打卡记录页 v2
import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../utils/time_utils.dart';
import '../theme/app_theme.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final AttendanceService _service = AttendanceService();
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1; int _totalPages = 0; String _stats = '';

  @override
  void initState() { super.initState(); _loadRecords(); }

  Future<void> _loadRecords({int page = 1}) async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await _service.getRecords(page: page, pageSize: 20);
      final pagination = result['pagination'] as Map<String, dynamic>?;
      setState(() {
        _records = (result['records'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        _page = pagination?['page'] as int? ?? 1;
        _totalPages = pagination?['totalPages'] as int? ?? 0;
        _stats = '共 ${pagination?['total'] ?? 0} 条';
        _isLoading = false;
      });
    } catch (e) { setState(() { _error = '加载失败'; _isLoading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打卡记录'), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text(_stats, style: const TextStyle(fontSize: 13))))]),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _records.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _records.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 16), ElevatedButton(onPressed: () => _loadRecords(), child: const Text('重试')),
      ]));
    }
    if (_records.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12), Text('暂无打卡记录', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () => _loadRecords(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _records.length + (_page < _totalPages ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          if (index >= _records.length) {
            return Padding(padding: const EdgeInsets.all(16), child: Center(child: TextButton(onPressed: () => _loadRecords(page: _page + 1), child: const Text('加载更多...'))));
          }
          final record = _records[index];
          final isCheckin = (record['type'] as String? ?? 'checkin') == 'checkin';
          return ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: isCheckin ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
              child: Icon(isCheckin ? Icons.login : Icons.logout, color: isCheckin ? const Color(0xFF16A34A) : const Color(0xFFF59E0B)),
            ),
            title: Text(isCheckin ? '签到' : '签退', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(record['address'] as String? ?? '位置未记录', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            trailing: Text(formatDateTimeFull(record['check_time'] as String?), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          );
        },
      ),
    );
  }
}

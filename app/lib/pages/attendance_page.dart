// 打卡记录页面

import 'package:flutter/material.dart';
import '../services/attendance_service.dart';

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
  int _page = 1;
  int _totalPages = 0;
  String _stats = '';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getRecords(page: page, pageSize: 20);
      final pagination = result['pagination'] as Map<String, dynamic>?;
      setState(() {
        _records = (result['records'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ?? [];
        _page = pagination?['page'] as int? ?? 1;
        _totalPages = pagination?['totalPages'] as int? ?? 0;
        _stats = '共 ${pagination?['total'] ?? 0} 条记录';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败，请稍后重试';
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '--';
    try {
      final dt = DateTime.parse(timestamp);
      // 使用设备当前时区偏移，替代硬编码UTC+8
      final offset = DateTime.now().timeZoneOffset;
      final local = dt.add(offset);
      return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡记录'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(_stats, style: const TextStyle(fontSize: 13))),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => _loadRecords(), child: const Text('重试')),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无打卡记录', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadRecords(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _records.length + (_page < _totalPages ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _records.length) {
            // 加载更多
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: TextButton(
                  onPressed: () => _loadRecords(page: _page + 1),
                  child: const Text('加载更多...'),
                ),
              ),
            );
          }

          final record = _records[index];
          final type = record['type'] as String? ?? 'checkin';
          final isCheckin = type == 'checkin';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isCheckin ? Colors.green[100] : Colors.orange[100],
              child: Icon(
                isCheckin ? Icons.login : Icons.logout,
                color: isCheckin ? Colors.green : Colors.orange,
              ),
            ),
            title: Text(isCheckin ? '签到' : '签退'),
            subtitle: Text(
              record['address'] as String? ?? '位置未记录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _formatTime(record['check_time'] as String?),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          );
        },
      ),
    );
  }
}

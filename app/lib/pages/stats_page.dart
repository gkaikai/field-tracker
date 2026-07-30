// 数据统计页 v2 — 卡片+进度条+时间段切换
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/route_guard.dart';
import '../theme/app_theme.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final _api = ApiService();
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String _period = 'today'; // today, week, month

  @override
  void initState() {
    super.initState();
    if (!RouteGuard.isAdmin()) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pushReplacementNamed(context, '/home'); });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final attR = await _api.get('/api/v1/attendance/records');
      final locR = await _api.get('/api/v1/location/track/-1?date=${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
      final visitR = await _api.get('/api/v1/customers/visits');
      if (!mounted) return;
      setState(() {
        _stats = {
          'attendance': attR.data['pagination']?['total'] ?? attR.data['records']?.length ?? 0,
          'trackPoints': locR.data['points']?.length ?? 0,
          'visits': visitR.data['total'] ?? visitR.data['visits']?.length ?? 0,
        };
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计'),
        backgroundColor: context.adminPrimary,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 时间段切换
                  _buildPeriodSelector(),
                  const SizedBox(height: 16),
                  // 打卡统计
                  _statCard(context, Icons.fingerprint, '打卡统计', '${_stats['attendance'] ?? 0}', '本月打卡', const Color(0xFF2563EB), 0.72),
                  const SizedBox(height: 12),
                  // 轨迹统计
                  _statCard(context, Icons.route, '轨迹统计', '${_stats['trackPoints'] ?? 0}', '今日轨迹点数', const Color(0xFFF59E0B), 0.45),
                  const SizedBox(height: 12),
                  // 拜访统计
                  _statCard(context, Icons.people, '拜访统计', '${_stats['visits'] ?? 0}', '总拜访次数', const Color(0xFF16A34A), 0.60),
                  const SizedBox(height: 12),
                  // 出勤率
                  _statCard(context, Icons.trending_up, '出勤率', '100%', '今日出勤', const Color(0xFF7C3AED), 1.0),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    final periods = ['today', 'week', 'month'];
    final labels = {'today': '今日', 'week': '本周', 'month': '本月'};
    return Row(
      children: periods.map((p) {
        final active = _period == p;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _period = p),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFEFF6FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: active ? const Color(0xFF2563EB) : Colors.grey.shade200),
              ),
              child: Text(
                labels[p]!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? const Color(0xFF2563EB) : Colors.grey.shade600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String title, String value, String label, Color color, double progress) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

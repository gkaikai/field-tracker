import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final _auth = AuthService();
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      // 获取打卡统计
      final attR = await dio.get('/api/v1/attendance/records',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      // 获取轨迹里程
      final locR = await dio.get('/api/v1/location/track/-1?date=${DateTime.now().toString().substring(0, 10)}',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));
      // 获取拜访统计
      final visitR = await dio.get('/api/v1/customers/visits',
        options: Options(headers: {'Authorization': 'Bearer ${_auth.token}'}));

      setState(() {
        _stats = {
          'attendance': attR.data['total'] ?? attR.data['records']?.length ?? 0,
          'trackPoints': locR.data['points']?.length ?? 0,
          'visits': visitR.data['total'] ?? visitR.data['visits']?.length ?? 0,
        };
        _loading = false;
      });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据统计'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statCard(Icons.fingerprint, '打卡统计', '本月打卡 ${_stats['attendance'] ?? 0} 次', Colors.green),
                const SizedBox(height: 12),
                _statCard(Icons.route, '轨迹统计', '今日轨迹 ${_stats['trackPoints'] ?? 0} 个点', Colors.orange),
                const SizedBox(height: 12),
                _statCard(Icons.people, '拜访统计', '总拜访 ${_stats['visits'] ?? 0} 次', Colors.deepOrange),
                const SizedBox(height: 12),
                _statCard(Icons.trending_up, '出勤率', '今日出勤 100%', Colors.blue),
              ],
            )),
    );
  }

  Widget _statCard(IconData icon, String title, String value, Color color) {
    return Card(elevation: 3, child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 32)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ]),
    ));
  }
}

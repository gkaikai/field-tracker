import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../services/background_location_service.dart';
import 'map_page.dart';
import 'attendance_page.dart';
import 'track_replay_page.dart';
import 'watermark_camera_page.dart';
import 'customer_page.dart';
import 'report_page.dart';
import 'fence_page.dart';
import 'profile_page.dart';
import 'attendance_rules_page.dart';
import 'approval_page.dart';
import 'stats_page.dart';
import 'photo_gallery_page.dart';
import 'visit_plan_page.dart';

/// 首页 - 功能导航
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _auth = AuthService();
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = pkg.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('外勤定位'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              LocationService().stopTracking();
              await stopBackgroundLocationService();
              await _auth.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        (_auth.userName ?? '?')[0],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_auth.userName ?? '未登录', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        Text('ID: ${(_auth.userId ?? '').length > 8 ? (_auth.userId!.substring(0, 8)) : (_auth.userId ?? '')}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 功能入口网格（2列）
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _card(Icons.map, '实时地图', '定位 & 打卡', Colors.blue,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()))),
                  _card(Icons.fingerprint, '打卡记录', '查看签到历史', Colors.green,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendancePage()))),
                  _card(Icons.route, '轨迹回放', '查看运动路线', Colors.orange,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackReplayPage()))),
                  _card(Icons.camera_alt, '拍照水印', '打卡拍照带水印', Colors.purple,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatermarkCameraPage()))),
                  _card(Icons.photo_library, '照片列表', '查看已拍照片', Colors.pink,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotoGalleryPage()))),
                  _card(Icons.fence, '电子围栏', '围栏管理', Colors.indigo,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FencePage()))),
                  _card(Icons.assignment, '工作汇报', '日报/周报', Colors.teal,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPage()))),
                  _card(Icons.people, '客户管理', '客户资料/拜访', Colors.deepOrange,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPage()))),
                  _card(Icons.checklist, '打卡规则', '考勤配置', Colors.brown,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceRulesPage()))),
                  _card(Icons.approval, '审批', '请假/出差', Colors.red,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalPage()))),
                  _card(Icons.bar_chart, '数据统计', '报表/里程', Colors.cyan,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsPage()))),
                  _card(Icons.person, '个人设置', '密码/信息', Colors.grey,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))),
                  _card(Icons.calendar_today, '拜访计划', '计划/路线', Colors.amber,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VisitPlanPage()))),
                  _card(Icons.settings, '权限设置', '定位权限引导', Colors.blueGrey,
                    () => Navigator.pushNamed(context, '/permission')),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 24,
        color: Colors.grey[50],
        child: Center(
          child: Text(
            _appVersion.isNotEmpty ? 'v$_appVersion' : '',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ),
    );
  }

  Widget _card(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }
}

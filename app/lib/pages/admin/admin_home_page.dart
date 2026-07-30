/// 管理员首页 — 仅展示管理功能
library;
import 'package:flutter/material.dart';
import 'package:field_tracker/services/amap_location_service.dart';
import 'package:field_tracker/services/background_location_service.dart';
import '../../services/auth_service.dart';
import '../../services/update_service.dart';
import '../../services/route_guard.dart';
import '../../widgets/home_card.dart';
import '../map_page.dart';
import '../track_replay_page.dart';
import '../fence_page.dart';
import '../customer_page.dart';
import '../stats_page.dart';
import './admin_dashboard_page.dart';
import '../attendance_page.dart';
import '../approval_page.dart';
import '../attendance_rules_page.dart';
import '../photo_gallery_page.dart';
import 'employee_management_page.dart';
import '../employee/employee_dashboard_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
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
      if (mounted) setState(() => _appVersion = '${pkg.version}+${pkg.buildNumber}');
    } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (updateInfo != null) {
        await UpdateService.showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查更新失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 路由守卫：非管理员直接返回空白
    if (!RouteGuard.isAdmin()) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理后台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: '查看我的数据',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmployeeDashboardPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              AmapLocationService().stopTracking();
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
            // 管理员信息卡片
            Card(
              color: Colors.indigo[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.indigo[100],
                      child: Text(
                        ((_auth.userName ?? '?').isNotEmpty ? _auth.userName![0] : '?'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_auth.userName ?? '未登录', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.indigo[100],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.indigo[300]!),
                                ),
                                child: Text('管理员', style: TextStyle(fontSize: 11, color: Colors.indigo[700])),
                              ),
                              const SizedBox(width: 8),
                              Text('工号: ${_auth.userCode ?? "—"}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 团队实时概览
            Card(
              color: const Color(0xFFF5F3FF),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('🟢 在线: 12人', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        Text('✅ 签到: 8/15人', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 8/15,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('今日出勤率 53%', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 管理功能网格
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  HomeCard(
                    icon: Icons.monitor_heart, title: '实时监控', subtitle: '全员位置地图', color: Colors.indigo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage())),
                  ),
                  HomeCard(
                    icon: Icons.route, title: '轨迹回放', subtitle: '查任意人轨迹', color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackReplayPage())),
                  ),
                  HomeCard(
                    icon: Icons.dashboard, title: '驾驶舱', subtitle: '团队数据总览', color: Colors.deepPurple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardPage())),
                  ),
                  HomeCard(
                    icon: Icons.fence, title: '围栏管理', subtitle: '围栏创建/编辑', color: Colors.teal,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FencePage())),
                  ),
                  HomeCard(
                    icon: Icons.people, title: '员工管理', subtitle: '管理员工账号', color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementPage())),
                  ),
                  HomeCard(
                    icon: Icons.bar_chart, title: '打卡统计', subtitle: '考勤数据看板', color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendancePage())),
                  ),
                  HomeCard(
                    icon: Icons.approval, title: '审批处理', subtitle: '审批他人申请', color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalPage())),
                  ),
                  HomeCard(
                    icon: Icons.checklist, title: '打卡规则', subtitle: '考勤规则配置', color: Colors.brown,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceRulesPage())),
                  ),
                  HomeCard(
                    icon: Icons.photo_library, title: '水印照片', subtitle: '查看全员照片', color: Colors.pink,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotoGalleryPage())),
                  ),
                  HomeCard(
                    icon: Icons.people_outline, title: '客户管理', subtitle: '客户资料/拜访', color: Colors.deepOrange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPage())),
                  ),
                  HomeCard(
                    icon: Icons.analytics, title: '数据统计', subtitle: '报表/里程', color: Colors.cyan,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsPage())),
                  ),
                  HomeCard(
                    icon: Icons.person, title: '我的数据', subtitle: '查看员工视角信息', color: Colors.grey,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeDashboardPage())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

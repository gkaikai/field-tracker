import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:field_tracker/services/amap_location_service.dart';
import 'package:field_tracker/services/background_location_service.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../utils/device_info.dart';
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
import 'permission_guide_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页 - 功能导航
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  final AmapLocationService _locService = AmapLocationService();
  String _appVersion = '';
  final DateTime _appStartTime = DateTime.now(); // 首次启动时间门控

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVersion();
    _locService.startTracking().then((started) {
      if (!started) {
        debugPrint('[HomePage] 定位服务启动失败');
      }
    });
    _requestBatteryOptimizationExemption();
    // 首次安装弹出权限引导页
    _showFirstLaunchGuide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台恢复前台 → 检查定位服务是否还活着
      _checkAndRestartLocation();
    }
  }

  /// 从后台恢复时检查定位服务健康状态
  Future<void> _checkAndRestartLocation() async {
    debugPrint('[HomePage] 应用回到前台，检查定位服务状态');

    // 首次启动短时间内的切入/出不弹引导（GPS冷启动需3-30秒）
    final hasBeenRunning =
        DateTime.now().difference(_appStartTime).inSeconds > 30;

    final loc = AmapLocationService();
    if (!loc.isRunning || loc.currentLat == null) {
      debugPrint('[HomePage] 定位服务不在运行或未收到位置，正在重启...');
      loc.stopTracking();
      await loc.startTracking();
      await startBackgroundLocationService();
      debugPrint('[HomePage] 定位服务已重启');
      // 运行超过30秒且后台被杀过，提示用户设置保活
      if (hasBeenRunning) {
        _showBatteryGuideDialog();
      }
    } else {
      debugPrint('[HomePage] 定位服务正常运行，最后位置: ${loc.currentLat}, ${loc.currentLng}');
    }
  }

  /// 请求忽略电池优化（华为/小米防御）
  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
        debugPrint('[HomePage] 已请求电池优化忽略');
      }
    } catch (e) {
      debugPrint('[HomePage] 请求电池优化忽略失败: $e');
    }
  }

  /// 首次安装弹出权限引导页
  Future<void> _showFirstLaunchGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('background_guide_done') ?? false;
      if (!done && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PermissionGuidePage()),
        );
      }
    } catch (e) {
      debugPrint('[HomePage] 权限引导页加载失败: $e');
    }
  }

  /// 显示后台保活引导弹窗（根据手机品牌自动匹配引导步骤）
  Future<void> _showBatteryGuideDialog() async {
    if (!mounted) return;

    final guide = await DeviceInfo.getGuideInfo();
    final title = guide['title'] ?? '后台定位设置引导';
    final steps = guide['steps'] ?? '请在系统设置中允许应用后台运行。';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(steps)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('已设置'),
          ),
          TextButton(
            onPressed: () async {
              // 再次请求忽略电池优化
              if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
                await Permission.ignoreBatteryOptimizations.request();
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('再去系统设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = pkg.version);
    } catch (_) {}
  }

  /// 检查更新并弹出对话框（委托给 UpdateService）
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
          SnackBar(content: Text('检查更新失败: $e')),
        );
      }
      debugPrint('[Update] 首页手动检查更新失败: $e');
    }
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
                        Text('工号: ${_auth.userCode ?? "—"}',
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
      bottomNavigationBar: GestureDetector(
        onTap: _checkForUpdate,
        child: Container(
          height: 24,
          color: Colors.grey[50],
          child: Center(
            child: Text(
              _appVersion.isNotEmpty ? 'v$_appVersion 点击检查更新' : '',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
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

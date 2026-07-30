/// 员工首页 — 工作台模式（考勤卡片+待办+快捷操作+数据概览）
library;
import 'package:flutter/material.dart';
import 'package:field_tracker/services/amap_location_service.dart';
import 'package:field_tracker/services/background_location_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../widgets/home_card.dart';
import '../map_page.dart';
import '../clock_page.dart';
import '../attendance_page.dart';
import '../visit_exec_page.dart';
import '../expense_page.dart';
import '../track_replay_page.dart';
import '../watermark_camera_page.dart';
import '../photo_gallery_page.dart';
import '../report_page.dart';
import '../approval_page.dart';
import '../profile_page.dart';
import '../permission_guide_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/time_utils.dart';

class EmployeeHomePage extends StatefulWidget {
  const EmployeeHomePage({super.key});

  @override
  State<EmployeeHomePage> createState() => _EmployeeHomePageState();
}

class _EmployeeHomePageState extends State<EmployeeHomePage>
    with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  DateTime? _lastGpsRestart; // GPS冷启动门控

  // 工作台数据
  Map<String, dynamic> _dashboardData = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AmapLocationService().startTracking().then((started) {
      if (!started) {
        debugPrint('[EmployeeHome] 定位服务启动失败');
      }
    });
    _requestBatteryOptimizationExemption();
    _loadDashboard();
    // 延迟执行导航相关操作，等 widget 树构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstLaunchGuide();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRestartLocation();
      _loadDashboard(); // 回到前台刷新数据
    }
  }

  Future<void> _loadDashboard() async {
    try {
      final resp = await _api.get('/api/v1/attendance/my-status');
      if (mounted) {
        setState(() {
          _dashboardData = resp.data as Map<String, dynamic>;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('[EmployeeHome] 加载工作台数据失败: $e');
      if (mounted) {
        setState(() {
          _dashboardData = {};
          _error = '加载失败，请下拉刷新';
        });
      }
    }
  }

  Future<void> _checkAndRestartLocation() async {
    debugPrint('[EmployeeHome] 应用回到前台，检查定位服务状态');
    // GPS冷启动门控：30秒内不重复重启
    if (_lastGpsRestart != null &&
        DateTime.now().difference(_lastGpsRestart!).inSeconds < 30) {
      debugPrint('[EmployeeHome] GPS冷启动门控触发，跳过重启');
      return;
    }
    try {
      final loc = AmapLocationService();
      if (!loc.isRunning || loc.currentLat == null) {
        loc.stopTracking();
        await loc.startTracking();
        await startBackgroundLocationService();
        _lastGpsRestart = DateTime.now();
      }
    } catch (e) {
      debugPrint('[EmployeeHome] 重启定位失败: $e');
    }
  }

  Future<void> _showFirstLaunchGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('background_guide_done') ?? false;
      if (!done && mounted) {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PermissionGuidePage()));
      }
    } catch (_) {}
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final today = _dashboardData['today'] as Map<String, dynamic>? ?? {};
    final checkedIn = today['checkedIn'] == true;
    final checkedOut = today['checkedOut'] == true;
    final monthly =
        _dashboardData['monthly'] as Map<String, dynamic>? ?? {};
    final pendingCount =
        (_dashboardData['pendingApprovalCount'] as int?) ?? 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('工作台'),
        actions: [
          if (pendingCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ApprovalPage())),
                ),
                Positioned(
                  right: 8,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ApprovalPage())),
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
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadDashboard();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 错误提示
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Colors.red[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Colors.red[700], fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              // ======== 用户信息 + 考勤状态 ========
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          ((_auth.userName ?? '?').isNotEmpty
                                  ? _auth.userName![0]
                                  : '?'),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_auth.userName ?? '未登录',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.blue[200]!),
                                  ),
                                  child: Text('员工',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue[700])),
                                ),
                                const SizedBox(width: 8),
                                if (_auth.userCode != null &&
                                    _auth.userCode!.isNotEmpty)
                                  Text('工号: ${_auth.userCode}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500])),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ======== 考勤状态卡片 ========
              _buildAttendanceCard(checkedIn, checkedOut, today),
              const SizedBox(height: 12),

              // ======== 快捷操作 ========
              const Text('快捷操作',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildQuickAction(
                    icon: Icons.fingerprint,
                    label: checkedIn ? '已签到' : '签到',
                    color: checkedIn ? Colors.green : Colors.blue,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ClockPage())),
                  ),
                  _buildQuickAction(
                    icon: Icons.camera_alt,
                    label: '水印拍照',
                    color: Colors.purple,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WatermarkCameraPage())),
                  ),
                  _buildQuickAction(
                    icon: Icons.route,
                    label: '我的轨迹',
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TrackReplayPage())),
                  ),
                  _buildQuickAction(
                    icon: Icons.assignment,
                    label: '工作汇报',
                    color: Colors.teal,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportPage())),
                  ),
                  _buildQuickAction(
                    icon: Icons.business,
                    label: '今日拜访',
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const VisitExecPage())),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ======== 月度数据概览（点击跳转考勤页） ========
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        Icons.calendar_today,
                        '${monthly['checkinDays'] ?? 0}',
                        '本月打卡',
                        Colors.blue,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AttendancePage())),
                      ),
                      Container(
                          height: 30,
                          width: 1,
                          color: Colors.grey[200]),
                      _buildStatItem(
                        Icons.trending_up,
                        '${monthly['totalDays'] ?? 0}',
                        '出勤天数',
                        Colors.green,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AttendancePage())),
                      ),
                      Container(
                          height: 30,
                          width: 1,
                          color: Colors.grey[200]),
                      _buildStatItem(
                        Icons.pending_actions,
                        '$pendingCount',
                        '待审批',
                        pendingCount > 0 ? Colors.red : Colors.grey,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ApprovalPage())),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ======== 常用功能（4个核心入口） ========
              const Text('常用功能',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  HomeCard(
                    icon: Icons.route,
                    title: '我的轨迹',
                    subtitle: '查看运动路线',
                    color: Colors.orange,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TrackReplayPage())),
                  ),
                  HomeCard(
                    icon: Icons.business,
                    title: '拜访记录',
                    subtitle: '今日拜访客户',
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const VisitExecPage())),
                  ),
                  HomeCard(
                    icon: Icons.photo_library,
                    title: '照片列表',
                    subtitle: '查看已拍照片',
                    color: Colors.pink,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PhotoGalleryPage())),
                  ),
                  HomeCard(
                    icon: Icons.person,
                    title: '个人设置',
                    subtitle: '密码/信息',
                    color: Colors.grey,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProfilePage())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(
      bool checkedIn, bool checkedOut, Map<String, dynamic> today) {
    final statusText = !checkedIn
        ? '未签到'
        : (checkedOut ? '已签退' : '已签到');
    final statusColor =
        !checkedIn ? Colors.orange : (checkedOut ? Colors.green : Colors.blue);
    final statusIcon = !checkedIn
        ? Icons.pending
        : (checkedOut ? Icons.check_circle : Icons.login);

    final recordsList = (today['records'] as List?) ?? [];
    // 已签退时取签到时间，未签退时取最后记录时间
    String displayTime;
    if (checkedOut) {
      final checkinRec = recordsList.cast<Map<String, dynamic>>().where(
          (r) => r['type'] == 'checkin').toList();
      displayTime = checkinRec.isNotEmpty
          ? formatTimestamp(checkinRec.first['check_time'] as String?)
          : '--:--';
    } else {
      displayTime = recordsList.isNotEmpty
          ? formatTimestamp(
              (recordsList.last as Map)['check_time'] as String?)
          : '--:--';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [statusColor.withAlpha(25), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(statusIcon, size: 32, color: statusColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusText,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: statusColor)),
                  const SizedBox(height: 4),
                  Text('今日上班: $displayTime',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String value, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

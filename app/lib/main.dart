import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/update_service.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/permission_guide_page.dart';
import 'package:workmanager/workmanager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局异常捕获
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 初始化WorkManager（后台定位用）
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  } catch (e) {
    debugPrint('WorkManager init skipped: $e');
  }

  // 尝试恢复登录态
  final authService = AuthService();
  final isLoggedIn = await authService.restoreSession();

  // 初始化高德定位SDK（隐私合规+API Key）
  LocationService.initSdk();

  // 注册WorkManager周期性定位任务
  try {
    registerPeriodicLocationTask();
  } catch (e) {
    debugPrint('PeriodicTask register skipped: $e');
  }

  runApp(FieldTrackerApp(isLoggedIn: isLoggedIn));
}

class FieldTrackerApp extends StatefulWidget {
  final bool isLoggedIn;

  const FieldTrackerApp({super.key, required this.isLoggedIn});

  @override
  State<FieldTrackerApp> createState() => _FieldTrackerAppState();
}

class _FieldTrackerAppState extends State<FieldTrackerApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 等框架构建完成后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (updateInfo != null && _navigatorKey.currentContext != null) {
        await UpdateService.showUpdateDialog(
            _navigatorKey.currentContext!, updateInfo);
      }
    } catch (e) {
      debugPrint('[Update] 检查更新异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '外勤定位',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: widget.isLoggedIn ? const HomePage() : const LoginPage(),
    );
  }
}

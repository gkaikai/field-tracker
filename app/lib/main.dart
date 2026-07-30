import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/update_service.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/permission_guide_page.dart';
import 'package:workmanager/workmanager.dart';
import 'config/app_config.dart';
import 'config/amap_key.dart';
import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();

  // 高德SDK隐私合规声明
  AMapFlutterLocation.updatePrivacyShow(true, true);
  AMapFlutterLocation.updatePrivacyAgree(true);
  // Flutter插件3.x必须在Dart代码中设置ApiKey（AndroidManifest无效）
  // 密钥通过 AMapConfig 从 --dart-define 编译注入
  AMapFlutterLocation.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey);

  // 全局异常捕获
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 尝试恢复登录态
  final authService = AuthService();
  final isLoggedIn = await authService.restoreSession();

  // 注册WorkManager周期性定位任务（后台保活）
  try {
    await Workmanager().registerPeriodicTask(
      'location-background',
      'locationTask',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
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
      theme: FieldTrackerTheme.light,
      darkTheme: FieldTrackerTheme.dark,
      home: widget.isLoggedIn ? const HomePage() : const LoginPage(),
      routes: {
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/permission': (context) => const PermissionGuidePage(),
        '/forgot-password': (context) => const ForgotPasswordPage(),
      },
    );
  }
}

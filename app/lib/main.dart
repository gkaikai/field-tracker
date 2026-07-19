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

  // 注册WorkManager周期性定位任务
  try {
    registerPeriodicLocationTask();
  } catch (e) {
    debugPrint('PeriodicTask register skipped: $e');
  }

  runApp(FieldTrackerApp(isLoggedIn: isLoggedIn));
}

class FieldTrackerApp extends StatelessWidget {
  final bool isLoggedIn;

  const FieldTrackerApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    // 启动时检查更新
    if (isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkUpdate(context);
      });
    }

    return MaterialApp(
      title: '外勤定位',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/permission': (context) => const PermissionGuidePage(),
      },
    );
  }
}

/// 检查新版本
Future<void> _checkUpdate(BuildContext context) async {
  try {
    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && context.mounted) {
      await UpdateService.showUpdateDialog(context, updateInfo);
    }
  } catch (e) {
    debugPrint('[Update] 检查更新异常: $e');
  }
}

/// 角色路由守卫 — 防止员工直接访问管理员页面
///
/// 使用方式:
/// 在需要保护的管理页面 build 方法开头调用:
///   if (!RouteGuard.isAdmin(context)) return const SizedBox.shrink();
library;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'app_role.dart';

class RouteGuard {
  /// 检查当前用户是否是管理员（使用 AppRole 枚举）
  static bool isAdmin() {
    return AuthService().isAdmin;
  }

  /// 检查当前用户是否是员工
  static bool isEmployee() {
    return AuthService().isEmployee;
  }

  /// 获取当前用户的角色中文名称
  static String getRoleLabel() {
    return AppRole.label(AuthService().role);
  }

  /// 包装页面：非管理员则重定向回首页
  static Widget guard(Function pageBuilder) {
    if (!isAdmin()) {
      return _RedirectHome();
    }
    return pageBuilder();
  }
}

/// 重定向到首页的占位widget
class _RedirectHome extends StatefulWidget {
  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('无权限访问')),
    );
  }
}

/// 主框架 — 4 Tab 底部导航
/// 统一员工端和管理端的导航结构
library;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/app_role.dart';
import '../pages/map_page.dart';
import '../pages/employee/employee_home_page.dart';
import '../pages/admin/admin_home_page.dart';
import '../theme/app_theme.dart';

/// 主导航 Tab 定义
enum MainTab {
  workbench('工作台', Icons.dashboard),
  map('地图', Icons.map),
  messages('消息', Icons.notifications_outlined),
  profile('我的', Icons.person_outline);

  final String label;
  final IconData icon;
  const MainTab(this.label, this.icon);
}

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppRole.isAdmin(_auth.role);
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: 工作台 (员工/管理不同)
          isAdmin ? const AdminHomePage() : const EmployeeHomePage(),
          // Tab 1: 地图
          const MapPage(),
          // Tab 2: 消息 (占位)
          _buildPlaceholder('消息通知', Icons.notifications_outlined),
          // Tab 3: 我的 (占位)
          _buildPlaceholder('个人中心', Icons.person_outline),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: isAdmin
            ? context.adminPrimary
            : theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.4),
        selectedLabelStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w400,
        ),
        items: [
          _navItem(MainTab.workbench, isAdmin ? Icons.dashboard : Icons.dashboard),
          _navItem(MainTab.map, Icons.map),
          _navItem(MainTab.messages, Icons.notifications_outlined, badge: 3),
          _navItem(MainTab.profile, Icons.person_outline),
        ],
      ),
    );
  }

  BottomNavigationBarItem _navItem(MainTab tab, IconData icon, {int? badge}) {
    return BottomNavigationBarItem(
      icon: badge != null
          ? Badge(
              label: Text('$badge', style: const TextStyle(fontSize: 9)),
              child: Icon(icon),
            )
          : Icon(icon),
      activeIcon: badge != null
          ? Badge(
              label: Text('$badge', style: const TextStyle(fontSize: 9)),
              child: Icon(icon, weight: 600),
            )
          : Icon(icon, weight: 600),
      label: tab.label,
    );
  }

  Widget _buildPlaceholder(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('$title\n开发中...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// 主框架 — 4 Tab 底部导航
library;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/app_role.dart';
import '../pages/map_page.dart';
import '../pages/messages_page.dart';
import '../pages/profile_page.dart';
import '../pages/employee/employee_home_page.dart';
import '../pages/admin/admin_home_page.dart';
import '../theme/app_theme.dart';

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
  int _messageBadge = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _messageBadge = messagesUnreadCount.value;
    messagesUnreadCount.addListener(_onUnreadChanged);
  }

  @override
  void dispose() {
    messagesUnreadCount.removeListener(_onUnreadChanged);
    super.dispose();
  }

  void _onUnreadChanged() {
    if (mounted) {
      setState(() => _messageBadge = messagesUnreadCount.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppRole.isAdmin(_auth.role);
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          isAdmin ? const AdminHomePage() : const EmployeeHomePage(),
          const MapPage(),
          const MessagesPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: isAdmin ? context.adminPrimary : theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.4),
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        items: [
          _navItem(MainTab.workbench, Icons.dashboard),
          _navItem(MainTab.map, Icons.map),
          _navItem(MainTab.messages, Icons.notifications_outlined, badge: _messageBadge > 0 ? _messageBadge : null),
          _navItem(MainTab.profile, Icons.person_outline),
        ],
      ),
    );
  }

  BottomNavigationBarItem _navItem(MainTab tab, IconData icon, {int? badge}) {
    return BottomNavigationBarItem(
      icon: badge != null
          ? Badge(label: Text('$badge', style: const TextStyle(fontSize: 9)), child: Icon(icon))
          : Icon(icon),
      activeIcon: badge != null
          ? Badge(label: Text('$badge', style: const TextStyle(fontSize: 9)), child: Icon(icon))
          : Icon(icon),
      label: tab.label,
    );
  }
}

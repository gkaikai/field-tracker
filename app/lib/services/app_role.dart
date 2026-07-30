/// 应用角色枚举 — 替代魔法字符串
library;

class AppRole {
  static const String employee = 'employee';
  static const String admin = 'admin';
  static const String manager = 'manager';

  /// 判断是否是管理角色
  static bool isAdmin(String? role) => role == admin || role == manager;

  /// 获取中文标签
  static String label(String? role) {
    switch (role) {
      case admin: return '管理员';
      case manager: return '经理';
      case employee: return '员工';
      default: return '未知';
    }
  }

  /// 获取颜色索引
  static int colorIndex(String? role) {
    switch (role) {
      case admin: return 0;
      case manager: return 1;
      default: return 2;
    }
  }

  /// 所有可选角色列表
  static List<Map<String, String>> get allOptions => [
    {'value': employee, 'label': '员工'},
    {'value': admin, 'label': '管理员'},
    {'value': manager, 'label': '经理'},
  ];
}

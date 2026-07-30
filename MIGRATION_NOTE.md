// ─────────────────────────────────────────────
//  main.dart 修改方案（只改2处）
//  原: theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true, brightness: Brightness.light)
//  新: import theme + 替换成 FieldTrackerTheme.light
// ─────────────────────────────────────────────

// 在 main.dart 顶部加一行 import（第1处修改）
// import 'theme/app_theme.dart';

// 第85行原来是:
// theme: ThemeData(
//   colorSchemeSeed: Colors.blue,
//   useMaterial3: true,
//   brightness: Brightness.light,
// ),

// 替换为（第2处修改）:
// theme: FieldTrackerTheme.light,
// darkTheme: FieldTrackerTheme.dark,

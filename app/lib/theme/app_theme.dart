/// Field Tracker Design System — Theme 主题定义
/// 
/// 将此文件放入 app/lib/theme/ 目录
/// 在 main.dart 中 import 后替换 ThemeData 即可
/// 
/// 使用方式:
///   theme: FieldTrackerTheme.light,
///   darkTheme: FieldTrackerTheme.dark,
library;
import 'package:flutter/material.dart';

// ============================================================
//  颜色常量 — 直接对应设计方案
// ============================================================
class FTColors {
  // 品牌色
  static const Color primary = Color(0xFF2563EB);       // Blue-600
  static const Color adminPrimary = Color(0xFF7C3AED);  // Violet-600
  static const Color success = Color(0xFF16A34A);       // Green-600
  static const Color warning = Color(0xFFF59E0B);       // Amber-500
  static const Color error = Color(0xFFDC2626);         // Red-600
  static const Color info = Color(0xFF0EA5E9);          // Sky-500

  // 中性色
  static const Color textPrimary = Color(0xFF0F172A);   // Slate-900
  static const Color textSecondary = Color(0xFF475569); // Slate-600
  static const Color textHint = Color(0xFF94A3B8);      // Slate-400
  static const Color textDisabled = Color(0xFFCBD5E1);  // Slate-300
  static const Color background = Color(0xFFF8FAFC);    // Slate-50
  static const Color surface = Color(0xFFFFFFFF);       // White
  static const Color border = Color(0xFFE2E8F0);        // Slate-200
  
  // 暗黑模式
  static const Color darkBackground = Color(0xFF0F172A); // Slate-900
  static const Color darkSurface = Color(0xFF1E293B);   // Slate-800
  static const Color darkTextPrimary = Color(0xFFF1F5F9);// Slate-100
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF334155);    // Slate-700
}

// ============================================================
//  Design Tokens — 间距/圆角/阴影
// ============================================================
class FTSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double page = 16;
}

class FTRadius {
  static const double card = 12;
  static const double button = 10;
  static const double input = 8;
  static const double modal = 16;
  static const double badge = 6;
}

// ============================================================
//  Theme Extension — 自定义 Token（Material 3 没有的）
// ============================================================
class FieldTrackerThemeExtension extends ThemeExtension<FieldTrackerThemeExtension> {
  final Color adminPrimary;
  final Color success;
  final Color warning;
  final Color info;

  const FieldTrackerThemeExtension({
    required this.adminPrimary,
    required this.success,
    required this.warning,
    required this.info,
  });

  @override
  ThemeExtension<FieldTrackerThemeExtension> copyWith({
    Color? adminPrimary,
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return FieldTrackerThemeExtension(
      adminPrimary: adminPrimary ?? this.adminPrimary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  ThemeExtension<FieldTrackerThemeExtension> lerp(
    covariant ThemeExtension<FieldTrackerThemeExtension>? other,
    double t,
  ) {
    if (other is! FieldTrackerThemeExtension) return this;
    return FieldTrackerThemeExtension(
      adminPrimary: Color.lerp(adminPrimary, other.adminPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

// ============================================================
//  主题工厂
// ============================================================
class FieldTrackerTheme {
  // ---------- 亮色模式 ----------
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    
    // 色彩体系 — 对应设计方案 6 品牌色
    colorScheme: const ColorScheme.light(
      primary: FTColors.primary,           // #2563EB
      secondary: FTColors.adminPrimary,     // #7C3AED
      tertiary: FTColors.info,             // #0EA5E9
      error: FTColors.error,               // #DC2626
      surface: FTColors.surface,           // #FFFFFF
      // 容器色（用于浅色背景装饰）
      primaryContainer: Color(0xFFEFF6FF),  // Blue-50
      secondaryContainer: Color(0xFFF5F3FF), // Violet-50
      tertiaryContainer: Color(0xFFF0F9FF),  // Sky-50
      errorContainer: Color(0xFFFEF2F2),     // Red-50
      // 在上面颜色上的文字色
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: FTColors.textPrimary,
      onError: Colors.white,
    ),

    // 字体排版 — 对应设计方案 9 级文字
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: FTColors.textPrimary),
      displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: FTColors.textPrimary),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: FTColors.textPrimary),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FTColors.textPrimary),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: FTColors.textPrimary),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: FTColors.textPrimary),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: FTColors.textSecondary),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: FTColors.textHint),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: FTColors.textSecondary, letterSpacing: 0.5),
    ),

    // AppBar
    appBarTheme: const AppBarTheme(
      elevation: 0,  // 阴影放到 scrolledUnder 控制
      centerTitle: false,
      backgroundColor: FTColors.primary, // 蓝色底 + 白色字/图标
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      iconTheme: IconThemeData(color: Colors.white),
    ),

    // 卡片
    cardTheme: CardTheme(
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FTRadius.card)),
      margin: EdgeInsets.zero,
    ),

    // 按钮
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FTRadius.button)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // 输入框
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FTColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FTRadius.input),
        borderSide: const BorderSide(color: FTColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FTRadius.input),
        borderSide: const BorderSide(color: FTColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FTRadius.input),
        borderSide: const BorderSide(color: FTColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FTRadius.input),
        borderSide: const BorderSide(color: FTColors.error, width: 2),
      ),
      labelStyle: const TextStyle(fontSize: 14, color: FTColors.textSecondary),
    ),

    // 底部导航
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedItemColor: FTColors.primary,
      unselectedItemColor: FTColors.textHint,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    ),

    // 自定义扩展（管理端主色、成功/警告色）
    extensions: const [
      FieldTrackerThemeExtension(
        adminPrimary: FTColors.adminPrimary,
        success: FTColors.success,
        warning: FTColors.warning,
        info: FTColors.info,
      ),
    ],
  );

  // ---------- 暗黑模式 ----------
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF60A5FA),          // Blue-400 (暗黑模式下更亮)
      secondary: Color(0xFFA78BFA),         // Violet-400
      tertiary: Color(0xFF38BDF8),
      error: Color(0xFFF87171),
      surface: FTColors.darkSurface,
      primaryContainer: Color(0xFF1E3A5F),
      secondaryContainer: Color(0xFF2E1065),
      onPrimary: FTColors.darkTextPrimary,
      onSurface: FTColors.darkTextPrimary,
    ),

    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: FTColors.darkTextPrimary),
      bodySmall: TextStyle(fontSize: 13, color: FTColors.darkTextSecondary),
    ),

    cardTheme: CardTheme(
      color: FTColors.darkSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FTRadius.card)),
    ),

    extensions: const [
      FieldTrackerThemeExtension(
        adminPrimary: Color(0xFFA78BFA),
        success: Color(0xFF4ADE80),
        warning: Color(0xFFFBBF24),
        info: Color(0xFF38BDF8),
      ),
    ],
  );
}

// ============================================================
//  便捷工具 — 在页面中获取自定义颜色
// ============================================================
extension FTBuildContext on BuildContext {
  /// 管理端主色（页面重构用）
  Color get adminPrimary => Theme.of(this).extension<FieldTrackerThemeExtension>()!.adminPrimary;
  Color get successColor => Theme.of(this).extension<FieldTrackerThemeExtension>()!.success;
  Color get warningColor => Theme.of(this).extension<FieldTrackerThemeExtension>()!.warning;
  Color get infoColor => Theme.of(this).extension<FieldTrackerThemeExtension>()!.info;

  /// 角色对应的 AppBar 颜色
  Color appBarColor(bool isAdmin) => isAdmin ? adminPrimary : Theme.of(this).colorScheme.primary;
}

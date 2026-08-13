import 'package:flutter/material.dart';

/// 玻璃拟态（Glassmorphism）主题：基于 Material 3 的主题配置，
/// 支持 7 套主题色预设 + 深色模式，视觉语言为半透明玻璃卡片 + 柔光渐变背景。
///
/// 通过 `AppTheme.light(index)` / `AppTheme.dark(index)` 按索引取色，
/// 索引对应 `AppSettings.primaryColorIndex`（设置页取色器也消费 `primaries`）。
/// 仅扩展 [ThemeData]，不改动任何业务逻辑。
class AppTheme {
  AppTheme._();

  /// 7 套主题色预设，与设置页「主题色」取色器一一对应。
  /// 索引 0 为默认货场绿。
  static const List<Color> primaries = [
    Color(0xFF2E7D32), // 0: 货场绿（默认）
    Colors.blue, // 1: 蓝色
    Colors.indigo, // 2: 靛蓝
    Colors.orange, // 3: 橙色
    Colors.red, // 4: 红色
    Colors.teal, // 5: 青色
    Colors.purple, // 6: 紫色
  ];

  /// 玻璃拟态背景基色：深邃靛蓝（深色模式）/ 柔雾薰衣草（浅色模式）。
  static const Color glassDarkBackdrop = Color(0xFF0E1030);
  static const Color glassLightBackdrop = Color(0xFFEFF1FB);

  /// 背景装饰光斑配色：翡翠绿 + 活力橙 + 靛蓝，呼应「财务增长」主题。
  static const List<Color> backdropOrbs = [
    Color(0xFF10B981), // 翡翠绿
    Color(0xFFFF9142), // 活力橙
    Color(0xFF4F5BD5), // 靛蓝
  ];

  static ThemeData light(int primaryIndex) =>
      _createTheme(_seed(primaryIndex), Brightness.light);

  static ThemeData dark(int primaryIndex) =>
      _createTheme(_seed(primaryIndex), Brightness.dark);

  /// 按索引取色（越界时取模循环，避免越界崩溃）。
  static Color _seed(int index) => primaries[index % primaries.length];

  static ThemeData _createTheme(Color seedColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // 玻璃卡片：低不透明度白色叠加 + 细白描边，营造磨砂玻璃质感。
    final glassFill = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.55);
    final glassBorder = isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.white.withOpacity(0.65);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Scaffold 背景交由 AppBackground 装饰层绘制，此处保持透明以透出光斑渐变。
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      // 玻璃拟态卡片：半透明底 + 细描边 + 柔和投影，营造悬浮玻璃质感。
      cardTheme: CardTheme(
        elevation: isDark ? 0 : 6,
        shadowColor: isDark ? Colors.transparent : seedColor.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: glassBorder, width: 1.2),
        ),
        color: glassFill,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        foregroundColor: colorScheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withOpacity(isDark ? 0.35 : 0.22),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: glassBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: glassBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: glassBorder, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: isDark
            ? const Color(0xFF181B3C)
            : Colors.white.withOpacity(0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xFF181B3C)
            : Colors.white.withOpacity(0.98),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      textTheme: ThemeData().textTheme.copyWith(
        titleLarge: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()], // 数字等宽对齐
        ),
        bodySmall: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

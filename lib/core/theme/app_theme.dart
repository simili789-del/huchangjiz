import 'package:flutter/material.dart';

/// 基于 Material 3 的主题配置，支持 7 套主题色预设 + 深色模式。
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

  static ThemeData light(int primaryIndex) =>
      _createTheme(_seed(primaryIndex), Brightness.light);

  static ThemeData dark(int primaryIndex) =>
      _createTheme(_seed(primaryIndex), Brightness.dark);

  /// 按索引取色（越界时取模循环，避免越界崩溃）。
  static Color _seed(int index) =>
      primaries[index % primaries.length];

  static ThemeData _createTheme(Color seedColor, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // iOS 18 风格：大圆角、无投影、贴底容器色卡片。
      // 注意：CI 实际 Flutter < 3.10，使用 CardTheme（CardThemeData 在该版本不存在）。
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        color: colorScheme.surfaceContainer,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
      textTheme: ThemeData().textTheme.copyWith(
        titleLarge: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.w700,
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

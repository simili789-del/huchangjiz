import 'package:flutter/material.dart';

/// 基于 Material 3 的主题配置，支持 7 套主题色预设 + 深色模式。
///
/// iOS 18 现代审美：
/// - 背景色优先使用 #F2F2F7（浅色）
/// - 强调色使用柔和的深灰色 #1C1C1E
/// - 高频次圆角 radius 16–24
/// - 所有颜色通过 ThemeData / ColorScheme 暴露，页面禁止硬编码颜色
class AppTheme {
  AppTheme._();

  /// iOS 系统浅色背景
  static const Color iosSystemBackground = Color(0xFFF2F2F7);

  /// iOS 强调深灰（接近 label 色）
  static const Color iosLabel = Color(0xFF1C1C1E);

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
      primaries[((index % primaries.length) + primaries.length) %
          primaries.length];

  static ThemeData _createTheme(Color seedColor, Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      // 强制浅色背景贴近 iOS #F2F2F7
      surface: isLight ? iosSystemBackground : null,
      // 强调文字/图标使用柔和深灰
      onSurface: isLight ? iosLabel : null,
    ).copyWith(
      // 卡片等容器使用略亮/略暗的 surface
      surfaceContainer: isLight
          ? Colors.white
          : const Color(0xFF2C2C2E),
      surfaceContainerHighest: isLight
          ? const Color(0xFFE5E5EA)
          : const Color(0xFF3A3A3C),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isLight ? iosSystemBackground : colorScheme.surface,
      // iOS 18 风格：大圆角、无投影、贴底容器色卡片。
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: colorScheme.surfaceContainer,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isLight ? iosSystemBackground : colorScheme.surface,
        foregroundColor: isLight ? iosLabel : colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: isLight ? iosLabel : colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        backgroundColor: isLight ? Colors.white.withValues(alpha: 0.9) : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
            titleLarge: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: isLight ? iosLabel : null,
            ),
            titleMedium: TextStyle(
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: isLight ? iosLabel : null,
            ),
            headlineSmall: TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isLight ? iosLabel : null,
            ),
            bodyLarge: TextStyle(
              color: isLight ? iosLabel : colorScheme.onSurface,
            ),
            bodyMedium: TextStyle(
              color: isLight ? iosLabel : colorScheme.onSurface,
            ),
            bodySmall: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
      // 列表与 Cupertino 风格兼容
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

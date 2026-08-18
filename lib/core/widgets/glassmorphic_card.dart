import 'dart:ui';

import 'package:flutter/material.dart';

/// iOS 18 风格毛玻璃效果卡片。
///
/// 作为列表项与内容区块的基类组件，使用 BackdropFilter + 半透明填充
/// 实现现代磨砂玻璃质感。圆角默认 20，可通过 [borderRadius] 覆盖。
///
/// 颜色全部来自 Theme，禁止硬编码。
class GlassmorphicCard extends StatelessWidget {
  const GlassmorphicCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.blurSigma = 12,
    this.opacity = 0.72,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final double blurSigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // 浅色：接近 #F2F2F7 的半透明白；深色：半透明深灰
    final fillColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: opacity);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.55);

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          // 保证最小点击区域符合无障碍 44px
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: content,
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: content,
    );
  }
}

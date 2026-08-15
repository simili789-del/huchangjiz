import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 玻璃拟态全局背景：深邃底色 + 多个柔光模糊色斑，
/// 为悬浮其上的半透明玻璃卡片提供有层次感的视觉衬底。
///
/// 通过 [MaterialApp.builder] 包裹整个应用内容，纯装饰、不拦截任何交互
/// （使用 [IgnorePointer]），不改动任何业务逻辑或路由结构。
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdrop =
        isDark ? AppTheme.glassDarkBackdrop : AppTheme.glassLightBackdrop;
    const orbs = AppTheme.backdropOrbs;

    return Container(
      color: backdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Stack(
              children: [
                _Orb(
                  color: orbs[0],
                  size: 320,
                  alignment: const Alignment(-1.15, -1.05),
                  opacity: isDark ? 0.30 : 0.35,
                ),
                _Orb(
                  color: orbs[1],
                  size: 280,
                  alignment: const Alignment(1.2, -0.6),
                  opacity: isDark ? 0.24 : 0.30,
                ),
                _Orb(
                  color: orbs[2],
                  size: 360,
                  alignment: const Alignment(0.9, 1.25),
                  opacity: isDark ? 0.32 : 0.28,
                ),
                _Orb(
                  color: orbs[0],
                  size: 220,
                  alignment: const Alignment(-1.1, 0.85),
                  opacity: isDark ? 0.18 : 0.22,
                ),
                // 统一模糊，让色斑呈现柔和的「毛玻璃光晕」效果。
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  final Alignment alignment;
  final double opacity;

  const _Orb({
    required this.color,
    required this.size,
    required this.alignment,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

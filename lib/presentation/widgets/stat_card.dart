import 'package:flutter/material.dart';

import '../../core/widgets/glassmorphic_card.dart';

/// 数据概览卡片：左侧标题/副标题，右侧大数字。
/// 使用毛玻璃基类，符合 iOS 18 审美。
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Widget? trailing;
  final Color? valueColor;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.trailing,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassmorphicCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: valueColor ?? cs.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

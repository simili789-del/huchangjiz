import 'package:flutter/material.dart';

import '../../core/constants/job_types.dart';

/// 作业类型计数卡片：彩色圆点 + 名称/单价 + 大数字 + - / + / +5。
/// 玻璃拟态风格：色点带柔光光晕，操作按钮为半透明玻璃胶囊。
class JobTypeCard extends StatelessWidget {
  final String jobType;
  final int quantity;
  final double unitPrice;
  final ValueChanged<int> onChanged;

  const JobTypeCard({
    super.key,
    required this.jobType,
    required this.quantity,
    required this.unitPrice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = DefaultJobTypes.colorOf(jobType);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.65),
                    blurRadius: 10,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    jobType,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '¥${unitPrice.toStringAsFixed(2)}/车',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.remove,
              onPressed: quantity > 0 ? () => onChanged(-1) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              color: cs.primary,
              onPressed: () => onChanged(1),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 36,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: cs.primary.withOpacity(0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: cs.primary.withOpacity(0.5)),
                ),
                onPressed: () => onChanged(5),
                child: Text('+5', style: TextStyle(color: cs.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? Theme.of(context).colorScheme.primary;
    return IconButton(
      icon: Icon(icon, color: onPressed == null ? btnColor.withOpacity(0.35) : btnColor),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: btnColor.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

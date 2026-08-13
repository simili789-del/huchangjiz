import 'package:flutter/material.dart';

import '../../core/constants/job_types.dart';

/// 作业类型计数卡片：彩色圆点 + 名称/单价 + 大数字 + - / + / +5。
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
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: (color ?? Theme.of(context).colorScheme.primary)
            .withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

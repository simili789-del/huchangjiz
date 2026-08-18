import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/glassmorphic_card.dart';
import '../../domain/entities/work_record.dart';

/// 明细页记录卡片：头像/班次标签 + 信息摘要 + 编辑删除 + 金额。
/// 基于 GlassmorphicCard，符合 iOS 18 毛玻璃审美。
class RecordListCard extends StatelessWidget {
  final WorkRecord record;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const RecordListCard({
    super.key,
    required this.record,
    this.isSelected = false,
    this.onToggleSelect,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalQty = record.jobQuantities.values.fold<int>(0, (a, b) => a + b);
    final isNight = record.shift == ShiftType.night;
    final shiftColor = isNight ? cs.secondaryContainer : cs.tertiaryContainer;
    final shiftTextColor =
        isNight ? cs.onSecondaryContainer : cs.onTertiaryContainer;

    final summary = record.jobQuantities.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}${e.value}车')
        .join(' · ');

    return GlassmorphicCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (onToggleSelect != null)
            Checkbox(
              value: isSelected,
              onChanged: (_) => onToggleSelect!(),
            )
          else
            CircleAvatar(
              backgroundColor: shiftColor,
              child: Text(
                record.workerName.isNotEmpty ? record.workerName[0] : '?',
                style: TextStyle(color: shiftTextColor),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        record.workerName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: shiftColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        record.shift.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: shiftTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('MM-dd').format(record.date)} · ${record.vehicleNo}${record.boatName != null && record.boatName!.isNotEmpty ? ' · ${record.boatName}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (summary.isNotEmpty)
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (record.remark != null && record.remark!.isNotEmpty)
                  Text(
                    record.remark!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalQty车',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                      color: cs.primary,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onDelete,
                      color: cs.error,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

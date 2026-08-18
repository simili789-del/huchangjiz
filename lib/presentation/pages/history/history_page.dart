import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/work_record.dart';
import '../../providers/history_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/selected_date_record_provider.dart';
import '../../widgets/record_list_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/yard_app_bar.dart';
import 'edit_record_page.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final records = ref.watch(historyRecordsProvider);
    final selected = ref.watch(selectedRecordIdsProvider);

    return Scaffold(
      appBar: YardAppBar(
        actions: [
          if (selected.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '批量删除',
              onPressed: () async {
                await ref
                    .read(recordRepositoryProvider)
                    .deleteRecords(selected.toList());
                // 批量删除后刷新：失效全量快照根即可级联刷新所有派生 Provider（含首页今日记账）
                ref.invalidate(allRecordsProvider);
                ref.invalidate(selectedDateRecordProvider);
                ref.read(selectedRecordIdsProvider.notifier).state = {};
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SectionHeader('近7天各类型车数'),
          const _Last7DaysSummary(),
          const SectionHeader('日期查询与筛选'),
          _FilterPanel(filter: filter),
          const SectionHeader('车数明细汇总'),
          _SummaryCard(records: records, filter: filter),
          const SectionHeader('记录列表'),
          records.isEmpty
              ? const _EmptyPlaceholder()
              : Column(
                  children: records
                      .map((r) => RecordListCard(
                            record: r,
                            isSelected: selected.contains(r.id),
                            onToggleSelect: () =>
                                _toggleSelect(ref, selected, r.id),
                            onEdit: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditRecordPage(record: r),
                                ),
                              );
                              // 编辑返回后刷新全部记录相关 Provider（含首页今日记账/统计）。
                              // H2：失效全量快照根即可级联刷新所有派生 Provider。
                              ref.invalidate(allRecordsProvider);
                              ref.invalidate(selectedDateRecordProvider);
                            },
                            onDelete: () async {
                              await ref
                                  .read(recordRepositoryProvider)
                                  .deleteRecords([r.id]);
                              // 删除后刷新所有记录相关 Provider（含首页今日记账）。
                              // H2：失效全量快照根即可级联刷新所有派生 Provider。
                              ref.invalidate(allRecordsProvider);
                              ref.invalidate(selectedDateRecordProvider);
                            },
                          ))
                      .toList(),
                ),
        ],
      ),
    );
  }

  void _toggleSelect(WidgetRef ref, Set<String> selected, String id) {
    final next = Set<String>.from(selected);
    selected.contains(id) ? next.remove(id) : next.add(id);
    ref.read(selectedRecordIdsProvider.notifier).state = next;
  }
}

class _Last7DaysSummary extends ConsumerWidget {
  const _Last7DaysSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(last7DaysSummaryProvider);
    final now = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: List.generate(7, (i) {
            final date = now.subtract(Duration(days: 6 - i));
            final key = DateTime(date.year, date.month, date.day);
            final dayRecords = summary[key] ?? [];
            final totalQty = dayRecords.fold<int>(
              0,
              (sum, r) =>
                  sum + r.jobQuantities.values.fold(0, (a, b) => a + b),
            );
            final detail = dayRecords
                .expand((r) => r.jobQuantities.entries)
                .where((e) => e.value > 0)
                .fold<Map<String, int>>({}, (map, e) {
              map[e.key] = (map[e.key] ?? 0) + e.value;
              return map;
            });
            final detailText = detail.entries
                .map((e) => '${e.key}${e.value}车')
                .join(' · ');

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      DateFormat('MM-dd').format(date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      dayRecords.isEmpty ? '—' : (detailText.isEmpty ? '—' : detailText),
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    dayRecords.isEmpty ? '—' : '$totalQty车',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FilterPanel extends ConsumerWidget {
  final HistoryFilter filter;

  const _FilterPanel({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (start, end) = filter.resolveDates();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: DateFormat('yyyy/MM/dd').format(start),
                    onTap: () => _pickDate(context, ref, isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('至'),
                ),
                Expanded(
                  child: _DateChip(
                    label: DateFormat('yyyy/MM/dd').format(end),
                    onTap: () => _pickDate(context, ref, isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _QuickChip(label: '今天', active: filter.range == QuickRange.today, onTap: () => _selectRange(ref, QuickRange.today)),
                _QuickChip(label: '近7天', active: filter.range == QuickRange.last7Days, onTap: () => _selectRange(ref, QuickRange.last7Days)),
                _QuickChip(label: '本月', active: filter.range == QuickRange.thisMonth, onTap: () => _selectRange(ref, QuickRange.thisMonth)),
                _QuickChip(label: '上月', active: filter.range == QuickRange.lastMonth, onTap: () => _selectRange(ref, QuickRange.lastMonth)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _QuickChip(
                  label: '全部班次',
                  active: filter.shift == null,
                  onTap: () => ref.read(historyFilterProvider.notifier).update(
                      (s) => s.copyWith(clearShift: true)),
                ),
                _QuickChip(
                  label: '白班',
                  active: filter.shift == ShiftType.day,
                  onTap: () => ref.read(historyFilterProvider.notifier).update(
                      (s) => s.copyWith(shift: ShiftType.day)),
                ),
                _QuickChip(
                  label: '夜班',
                  active: filter.shift == ShiftType.night,
                  onTap: () => ref.read(historyFilterProvider.notifier).update(
                      (s) => s.copyWith(shift: ShiftType.night)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: '搜索姓名/车号',
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                      filled: true,
                    ),
                    onChanged: (v) => ref
                        .read(historyFilterProvider.notifier)
                        .update((s) => s.copyWith(keyword: v)),
                  ),
                ),
                const SizedBox(width: 8),
                _SortButton(filter: filter),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectRange(WidgetRef ref, QuickRange range) {
    ref.read(historyFilterProvider.notifier).update((s) => s.copyWith(range: range));
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref,
      {required bool isStart}) async {
    final filter = ref.read(historyFilterProvider);
    final initial = isStart
        ? (filter.customStart ?? DateTime.now())
        : (filter.customEnd ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    ref.read(historyFilterProvider.notifier).update((s) => s.copyWith(
          range: QuickRange.custom,
          customStart: isStart ? picked : s.customStart,
          customEnd: isStart ? s.customEnd : picked,
        ));
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onTap(),
      selectedColor: cs.primaryContainer,
      labelStyle: TextStyle(
        color: active ? cs.onPrimaryContainer : null,
        fontWeight: active ? FontWeight.w600 : null,
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  final HistoryFilter filter;

  const _SortButton({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String label;
    switch (filter.sort) {
      case HistorySort.dateDesc:
        label = '日期 ↓';
      case HistorySort.dateAsc:
        label = '日期 ↑';
      case HistorySort.amountDesc:
        label = '金额 ↓';
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.sort, size: 18),
      label: Text(label),
      onPressed: () {
        final next = filter.sort == HistorySort.dateDesc
            ? HistorySort.dateAsc
            : filter.sort == HistorySort.dateAsc
                ? HistorySort.amountDesc
                : HistorySort.dateDesc;
        ref
            .read(historyFilterProvider.notifier)
            .update((s) => s.copyWith(sort: next));
      },
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final List<WorkRecord> records;
  final HistoryFilter filter;

  const _SummaryCard({required this.records, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitPrices = ref.watch(unitPricesProvider);
    final (start, end) = filter.resolveDates();
    final totalQty = records.fold<int>(
      0,
      (sum, r) => sum + r.jobQuantities.values.fold(0, (a, b) => a + b),
    );
    final totalAmount = records.fold<double>(
      0,
      (sum, r) => sum + r.amount(unitPrices),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${DateFormat('yyyy-MM-dd').format(start)} ~ ${DateFormat('yyyy-MM-dd').format(end)} (${records.length}条)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '合计: $totalQty车 · ¥${totalAmount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          '暂无符合条件的记录',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

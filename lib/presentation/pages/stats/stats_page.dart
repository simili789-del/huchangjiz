import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/job_types.dart';
import '../../../core/util/share_file.dart';
import '../../../data/serialization/record_serialization.dart';
import '../../providers/repository_providers.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/yard_app_bar.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(statsMonthProvider);
    final stats = ref.watch(monthlyStatsProvider);
    final workerFilter = ref.watch(statsWorkerFilterProvider);
    final allWorkers = stats.incomeByWorker.keys.toList();

    return Scaffold(
      appBar: YardAppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref
                .read(statsMonthProvider.notifier)
                .update((m) => DateTime(m.year, m.month - 1)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => ref
                .read(statsMonthProvider.notifier)
                .update((m) => DateTime(m.year, m.month + 1)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SectionHeader('月度选择'),
          _MonthSelector(
            month: month,
            workerFilter: workerFilter,
            workers: allWorkers,
          ),
          const SectionHeader('摘要核算（按单价）'),
          _PriceSummary(stats: stats),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: '月度计件收入',
                    value: '¥${stats.totalIncome.toStringAsFixed(2)}',
                    valueColor: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    title: '预估总工资',
                    value: '¥${stats.estimatedSalary.toStringAsFixed(2)}',
                    valueColor: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('每日车数柱状图'),
          _DailyBarChart(stats: stats),
          const SectionHeader('按单价分类汇总'),
          _PriceGroupList(stats: stats),
          const SectionHeader('作业类型分布'),
          _JobTypeDistribution(stats: stats),
          const SectionHeader('按人员统计'),
          _WorkerStats(stats: stats),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出本月 CSV'),
              onPressed: () async {
                try {
                  final month = ref.read(statsMonthProvider);
                  final start = DateTime(month.year, month.month, 1);
                  final end =
                      DateTime(month.year, month.month + 1, 0, 23, 59, 59);
                  final recs = ref
                      .read(recordRepositoryProvider)
                      .query(start: start, end: end);
                  if (recs.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('本月暂无数据可导出')),
                      );
                    }
                    return;
                  }
                  final csv = RecordSerialization.toCsv(
                    recs,
                    ref.read(unitPricesProvider),
                  );
                  final name =
                      '货场记账_${month.year}${month.month.toString().padLeft(2, '0')}.csv';
                  await shareTextFile(csv, name);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已导出 ${recs.length} 条记录')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('导出失败：$e')),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSelector extends ConsumerWidget {
  final DateTime month;
  final String workerFilter;
  final List<String> workers;

  const _MonthSelector({
    required this.month,
    required this.workerFilter,
    required this.workers,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: month,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked != null) {
                    ref
                        .read(statsMonthProvider.notifier)
                        .state = DateTime(picked.year, picked.month);
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy年MM月').format(month),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: workerFilter.isEmpty ? null : workerFilter,
                    hint: const Text('人员: 全部'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('人员: 全部'),
                      ),
                      ...workers.map((w) => DropdownMenuItem(
                            value: w,
                            child: Text(w),
                          )),
                    ],
                    onChanged: (v) => ref
                        .read(statsWorkerFilterProvider.notifier)
                        .state = v ?? '',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  final MonthlyStats stats;

  const _PriceSummary({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.quantityByPrice.isEmpty) {
      return const _EmptyCard(text: '本月暂无数据');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: () {
            final entries = stats.quantityByPrice.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));
            return entries.map((e) {
              final g = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '单价 ¥${g.price.toStringAsFixed(2)} · ${g.totalQty}车',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.wb_sunny_outlined, size: 16),
                        Text('${g.dayQty}'),
                        const SizedBox(width: 12),
                        const Icon(Icons.nights_stay_outlined, size: 16),
                        Text('${g.nightQty}'),
                      ],
                    ),
                  ],
                ),
              );
            }).toList();
          }(),
        ),
      ),
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  final MonthlyStats stats;

  const _DailyBarChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final days = stats.vehicleCountByDay.keys.toList()..sort();
    final maxY = stats.vehicleCountByDay.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Card(
      child: SizedBox(
        height: 220,
        child: days.isEmpty
            ? const Center(child: Text('本月暂无数据'))
            : Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 16,
                  top: 16,
                  bottom: 8,
                ),
                child: BarChart(
                  BarChartData(
                    maxY: (maxY < 5 ? 5 : maxY * 1.2).toDouble(),
                    barGroups: [
                      for (int i = 0; i < days.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: (stats.vehicleCountByDay[days[i]] ?? 0)
                                  .toDouble(),
                              width: 12,
                              borderRadius: BorderRadius.circular(4),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= days.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${days[i].day}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PriceGroupList extends StatelessWidget {
  final MonthlyStats stats;

  const _PriceGroupList({required this.stats});

  @override
  Widget build(BuildContext context) {
    final entries = stats.quantityByPrice.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      children: entries.map((e) {
        final g = e.value;
        final amount = g.totalQty * g.price;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '¥${g.price.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.jobTypes.join('、'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${g.totalQty}车 · ¥${amount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _JobTypeDistribution extends ConsumerWidget {
  final MonthlyStats stats;

  const _JobTypeDistribution({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitPrices = ref.watch(unitPricesProvider);
    return Column(
      children: stats.quantityByJobType.entries.map((e) {
        final color = DefaultJobTypes.colorOf(e.key);
        final price = unitPrices[e.key] ?? 0;
        final amount = e.value * price;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${e.value}车 · ¥${amount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WorkerStats extends StatelessWidget {
  final MonthlyStats stats;

  const _WorkerStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: stats.workerStats.map((w) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.name.isEmpty ? '（未填写姓名）' : w.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '白${w.dayQty} · 夜${w.nightQty}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${w.totalQty}车 · ¥${w.income.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

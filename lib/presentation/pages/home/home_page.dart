import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/job_types.dart';
import '../../../domain/entities/work_record.dart';
import '../../providers/history_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/selected_date_record_provider.dart';
import '../../widgets/job_type_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/yard_app_bar.dart';
import '../../pages/import/import_wizard_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: YardAppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: '导入 Excel',
            onPressed: () async {
              final picked = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['xlsx', 'xls', 'csv'],
              );
              final path = picked?.files.single.path;
              if (path != null && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ImportWizardPage(filePath: path)),
                );
              }
            },
          ),
        ],
      ),
      body: const _HomeBody(),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(selectedDateRecordProvider);
    final unitPrices = ref.watch(unitPricesProvider);
    final jobTypes = unitPrices.keys.isNotEmpty
        ? unitPrices.keys.toList()
        : DefaultJobTypes.types;
    final selectedDate = ref.watch(selectedDateProvider);

    return recordAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('加载失败：$e')),
      data: (record) => ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SectionHeader('快速记账'),
          _DateSelector(date: selectedDate),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _TextFieldCard(
                    label: '姓名',
                    value: record.workerName,
                    onChanged: (v) => ref
                        .read(selectedDateRecordProvider.notifier)
                        .updateBasicInfo(workerName: v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextFieldCard(
                    label: '车号',
                    value: record.vehicleNo,
                    onChanged: (v) => ref
                        .read(selectedDateRecordProvider.notifier)
                        .updateBasicInfo(vehicleNo: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ShiftSelector(
            shift: record.shift,
            onChanged: (s) => ref
                .read(selectedDateRecordProvider.notifier)
                .updateBasicInfo(shift: s),
          ),
          const SizedBox(height: 8),
          ...jobTypes.map((jobType) => JobTypeCard(
                jobType: jobType,
                quantity: record.jobQuantities[jobType] ?? 0,
                unitPrice: unitPrices[jobType] ?? 0,
                onChanged: (delta) => ref
                    .read(selectedDateRecordProvider.notifier)
                    .updateJobQuantity(jobType, delta),
              )),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextFormField(
              initialValue: record.remark,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '选填',
              ),
              maxLines: 2,
              onChanged: (v) => ref
                  .read(selectedDateRecordProvider.notifier)
                  .updateRemark(v),
            ),
          ),
          const SizedBox(height: 16),
          _SaveButton(record: record, unitPrices: unitPrices),
          const SectionHeader('今日摘要'),
          _SummaryCards(date: selectedDate),
          const SectionHeader('上次作业详情'),
          const _LastWorkDetail(),
        ],
      ),
    );
  }
}

class _DateSelector extends ConsumerWidget {
  final DateTime date;

  const _DateSelector({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        child: InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              ref.read(selectedDateProvider.notifier).state = picked;
              ref.read(selectedDateRecordProvider.notifier).reload();
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    DateFormat('yyyy/MM/dd').format(date),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextFieldCard extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TextFieldCard({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
      ),
      onChanged: onChanged,
    );
  }
}

class _SaveButton extends ConsumerWidget {
  final WorkRecord record;
  final Map<String, double> unitPrices;

  const _SaveButton({required this.record, required this.unitPrices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAmount = record.amount(unitPrices);
    final totalQty = record.jobQuantities.values.fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FilledButton.icon(
        icon: const Icon(Icons.check),
        label: Text('保存 · ¥${totalAmount.toStringAsFixed(2)} · $totalQty车'),
        onPressed: () async {
          await ref.read(selectedDateRecordProvider.notifier).save();
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已保存')));
          }
        },
      ),
    );
  }
}

class _SummaryCards extends ConsumerWidget {
  final DateTime date;

  const _SummaryCards({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitPrices = ref.watch(unitPricesProvider);
    // 聚合当天全部记录（「今日记账」纯日期记录 + 当天所有 imp_ 导入记录），
    // 使导入当天 Excel 后首页摘要同步更新。
    final dayRecords = ref.watch(dayRecordsProvider(date));
    final totalQty = dayRecords.fold<int>(
      0,
      (s, r) => s + r.jobQuantities.values.fold(0, (a, b) => a + b),
    );
    final totalAmount =
        dayRecords.fold<double>(0, (s, r) => s + r.amount(unitPrices));
    final dayQty = dayRecords
        .where((r) => r.shift == ShiftType.day)
        .fold<int>(0, (s, r) => s + r.jobQuantities.values.fold(0, (a, b) => a + b));
    final nightQty = dayRecords
        .where((r) => r.shift == ShiftType.night)
        .fold<int>(0, (s, r) => s + r.jobQuantities.values.fold(0, (a, b) => a + b));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              title: '今日车数',
              value: '$totalQty',
              subtitle: '☀白$dayQty · 🌙夜$nightQty',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              title: '今日收入',
              value: '¥${totalAmount.toStringAsFixed(2)}',
              subtitle: '昨日合计 0车 · ¥0.00',
              valueColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftSelector extends StatelessWidget {
  final ShiftType shift;
  final ValueChanged<ShiftType> onChanged;

  const _ShiftSelector({required this.shift, required this.onChanged});

  Widget _tile(
    BuildContext context,
    ShiftType value,
    String label,
    IconData icon,
    Color active,
  ) {
    final selected = shift == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? active : active.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? active : active.withOpacity(0.35),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : active, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : active,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _tile(context, ShiftType.day, '白班', Icons.wb_sunny, Colors.orange),
          const SizedBox(width: 12),
          _tile(
              context, ShiftType.night, '夜班', Icons.nights_stay, Colors.indigo),
        ],
      ),
    );
  }
}

class _LastWorkDetail extends ConsumerWidget {
  const _LastWorkDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastRecordProvider);
    return last.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (record) {
        if (record == null) {
          return Card(
            child: Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                '暂无历史记录',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade500),
              ),
            ),
          );
        }
        final unitPrices = ref.watch(unitPricesProvider);
        final totalQty = record.jobQuantities.values.fold<int>(
          0,
          (a, b) => a + b,
        );
        final amount = record.amount(unitPrices);
        final jobText = record.jobQuantities.entries
            .where((e) => e.value > 0)
            .map((e) => '${e.key} ${e.value}车')
            .join(' · ');
        final cs = Theme.of(context).colorScheme;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(record.date),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: record.shift == ShiftType.day
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.indigo.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            record.shift == ShiftType.day
                                ? Icons.wb_sunny
                                : Icons.nights_stay,
                            size: 14,
                            color: record.shift == ShiftType.day
                                ? Colors.orange
                                : Colors.indigo,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            record.shift.label,
                            style: TextStyle(
                              color: record.shift == ShiftType.day
                                  ? Colors.orange
                                  : Colors.indigo,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  record.workerName.isEmpty
                      ? '（未填写姓名）'
                      : record.workerName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (record.vehicleNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '车号：${record.vehicleNo}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (jobText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(jobText),
                ],
                const SizedBox(height: 8),
                Text(
                  '合计 $totalQty 车 · ¥${amount.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                ),
                if (record.boatName?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('船名：${record.boatName}'),
                ],
                if (record.remark?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    '备注：${record.remark}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/work_record.dart';
import '../../../data/repositories/excel_importer.dart';
import '../../providers/import_provider.dart';

/// Excel 导入向导：接收分享或手动选文件后进入。
/// 流程：解析 → 选 sheet/表头行 → 预览列映射 → 勾选人员 → 确认导入并同步作业类型。
class ImportWizardPage extends ConsumerStatefulWidget {
  final String filePath;
  const ImportWizardPage({super.key, required this.filePath});

  @override
  ConsumerState<ImportWizardPage> createState() => _ImportWizardPageState();
}

class _ImportWizardPageState extends ConsumerState<ImportWizardPage> {
  String? _sheetName;
  int? _headerRow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(importProvider.notifier)
          .loadFile(widget.filePath, sheetName: _sheetName, headerRow: _headerRow);
    });
  }

  Future<void> _reparse() async {
    await ref
        .read(importProvider.notifier)
        .loadFile(widget.filePath, sheetName: _sheetName, headerRow: _headerRow);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入 Excel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '取消',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(ImportUiState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _ErrorPanel(
        error: state.error!,
        onRetry: _reparse,
        headerRow: _headerRow,
        onHeaderRowChanged: (v) => setState(() => _headerRow = v),
      );
    }
    if (state.done) {
      return _SuccessPanel(count: state.importedCount);
    }
    final result = state.result;
    if (result == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (result.sheetNames.length > 1) _SheetSelector(result, _sheetName, (v) {
          setState(() => _sheetName = v);
          _reparse();
        }),
        if (!result.importable) ...[
          const SizedBox(height: 8),
          _NonImportablePanel(result),
        ] else ...[
          _HeaderRowTile(
            headerRow: result.headerRow,
            headerOverride: _headerRow,
            onChanged: (v) {
              setState(() => _headerRow = v);
              _reparse();
            },
          ),
          const SizedBox(height: 8),
          _MappingPreview(result, templateMatched: state.templateMatched),
          const SizedBox(height: 8),
          if (result.sheetTotals != null)
            _ReconcilePanel(
              result: result,
              computed: ref.read(importProvider.notifier).computedTotals,
              mismatches: ref.read(importProvider.notifier).mismatches,
            ),
          const SizedBox(height: 12),
          _DateShiftTile(
            date: state.date,
            shift: state.shift,
            onDate: (d) => ref.read(importProvider.notifier).setDate(d),
            onShift: (s) => ref.read(importProvider.notifier).setShift(s),
          ),
          const SizedBox(height: 12),
          if (state.focusedWorker != null || state.fixedWorkers.isNotEmpty)
            SwitchListTile(
              title: state.focusedWorker != null
                  ? Text('仅导入「${state.focusedWorker}」')
                  : const Text('仅导入固定人员名单内的人'),
              subtitle: const Text('关闭后可勾选表格中的其他人员'),
              value: state.enforceFixed,
              onChanged: (v) =>
                  ref.read(importProvider.notifier).setEnforceFixed(v),
            ),
          _WorkerList(state),
          const SizedBox(height: 80),
        ],
      ],
    );
  }
}

class _SheetSelector extends StatelessWidget {
  final ExcelParseResult result;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SheetSelector(this.result, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.table_chart),
      title: const Text('工作表'),
      trailing: DropdownButton<String>(
        value: value ?? result.sheetName,
        items: result.sheetNames
            .map((s) {
              final ok = result.sheetImportable?[s] ?? true;
              return DropdownMenuItem(
                value: s,
                child: Text(
                  ok ? s : '$s（非绩效表）',
                  style: ok
                      ? null
                      : Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                ),
              );
            })
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _HeaderRowTile extends StatelessWidget {
  final int headerRow;
  final int? headerOverride;
  final ValueChanged<int?> onChanged;
  const _HeaderRowTile(
      {required this.headerRow, required this.headerOverride, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(
        text: headerOverride?.toString() ?? headerRow.toString());
    return ListTile(
      leading: const Icon(Icons.format_list_numbered),
      title: Text(headerOverride == null
          ? '表头行：第 ${headerRow + 1} 行（自动识别）'
          : '表头行：第 ${headerOverride! + 1} 行（手动）'),
      trailing: SizedBox(
        width: 70,
        child: TextFormField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '行号'),
          keyboardType: TextInputType.number,
          onFieldSubmitted: (v) {
            final n = int.tryParse(v);
            onChanged(n != null && n > 0 ? n - 1 : null);
          },
        ),
      ),
    );
  }
}

class _MappingPreview extends StatelessWidget {
  final ExcelParseResult result;
  final bool templateMatched;
  const _MappingPreview(this.result, {this.templateMatched = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('识别到的列', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (templateMatched)
                  Chip(
                    label: const Text('已识别常用模板'),
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    backgroundColor:
                        Theme.of(context).colorScheme.tertiaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                const Chip(label: Text('姓名'), avatar: Icon(Icons.person)),
                if (result.vehCol != null)
                  const Chip(label: Text('车号'), avatar: Icon(Icons.local_shipping)),
                if (result.remarkCol != null)
                  const Chip(label: Text('备注'), avatar: Icon(Icons.note)),
                ...result.jobColumns.map((c) => Chip(
                      label: Text(c.price != null ? '${c.name}（¥${c.price}）' : c.name),
                      avatar: const Icon(Icons.build),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReconcilePanel extends StatelessWidget {
  final ExcelParseResult result;
  final Map<String, int> computed;
  final List<String> mismatches;
  const _ReconcilePanel({
    required this.result,
    required this.computed,
    required this.mismatches,
  });

  @override
  Widget build(BuildContext context) {
    final totals = result.sheetTotals!;
    final cols = totals.keys.toList();
    final hasMismatch = mismatches.isNotEmpty;
    return Card(
      color: hasMismatch ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(hasMismatch ? Icons.warning_amber : Icons.check_circle,
                    color: hasMismatch ? Colors.red : Colors.green),
                const SizedBox(width: 6),
                Text(
                  hasMismatch ? '对账不一致！' : '对账一致',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: hasMismatch ? Colors.red : Colors.green,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasMismatch
                  ? '勾选人员的车数合计与表格「合计」行不符，可能存在漏录，请核对后再导入'
                  : '勾选人员车数合计已与表格「合计」行完全一致',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...cols.map((col) {
              final t = totals[col]!;
              final c = computed[col] ?? 0;
              final bad = t != c;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(col)),
                    Text('表格 $t',
                        style: TextStyle(color: bad ? Colors.red : null)),
                    const SizedBox(width: 12),
                    Text('已选 $c',
                        style: TextStyle(
                          color: bad ? Colors.red : null,
                          fontWeight: bad ? FontWeight.bold : null,
                        )),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DateShiftTile extends StatelessWidget {
  final DateTime? date;
  final ShiftType shift;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<ShiftType> onShift;
  const _DateShiftTile(
      {required this.date, required this.shift, required this.onDate, required this.onShift});

  @override
  Widget build(BuildContext context) {
    final d = date ?? DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('作业日期'),
              trailing: Text(DateFormat('yyyy-MM-dd').format(d)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: d,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) onDate(picked);
              },
            ),
            SegmentedButton<ShiftType>(
              segments: const [
                ButtonSegment(value: ShiftType.day, label: Text('白班')),
                ButtonSegment(value: ShiftType.night, label: Text('夜班')),
              ],
              selected: {shift},
              onSelectionChanged: (s) => onShift(s.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerList extends ConsumerWidget {
  final ImportUiState state;
  const _WorkerList(this.state);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.result!;
    final allSelected = state.selectedWorkers.length == result.rows.length;
    final fixedSet = state.fixedWorkers.toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('人员与车数（勾选导入）',
                    style: Theme.of(context).textTheme.titleSmall),
                TextButton(
                  onPressed: () =>
                      ref.read(importProvider.notifier).selectAll(!allSelected),
                  child: Text(allSelected ? '全不选' : '全选'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...result.rows.map((row) {
              final selected = state.selectedWorkers.contains(row.workerName);
              final inFixed = fixedSet.contains(row.workerName);
              final disabled = state.enforceFixed && !inFixed;
              final qty = row.quantities.entries
                  .map((e) => '${e.key}:${e.value}')
                  .join('  ');
              return CheckboxListTile(
                value: selected,
                onChanged: disabled
                    ? null
                    : (v) => ref
                        .read(importProvider.notifier)
                        .toggleWorker(row.workerName, v ?? false),
                title: Text(row.workerName),
                subtitle: Text(
                  [
                    if (row.vehicleNo.isNotEmpty) '车号 ${row.vehicleNo}',
                    if (row.boatName != null && row.boatName!.isNotEmpty)
                      '船名 ${row.boatName}',
                    qty,
                    if (disabled) '非默认姓名（关闭上方开关可导入）',
                  ].where((s) => s.isNotEmpty).join('  ·  '),
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.cloud_download),
                label: Text('确认导入（${state.selectedWorkers.length} 人）'),
                onPressed: state.selectedWorkers.isEmpty
                    ? null
                    : () async {
                        final notifier = ref.read(importProvider.notifier);
                        await notifier.confirm();
                        final count = notifier.lastImportedCount;
                        final miss = notifier.mismatches;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: miss.isEmpty ? null : Colors.orange,
                              content: Text(
                                miss.isEmpty
                                    ? '已导入 $count 条，作业类型已更新，合计对账一致'
                                    : '已导入 $count 条，但 $miss 与表格合计不符，请核对',
                              ),
                            ),
                          );
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final int? headerRow;
  final ValueChanged<int?> onHeaderRowChanged;
  const _ErrorPanel({
    required this.error,
    required this.onRetry,
    required this.headerRow,
    required this.onHeaderRowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(
        text: headerRow != null ? (headerRow! + 1).toString() : '');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text('解析失败', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        const Text('若是表头行识别有误，可手动指定（填第几行，从 1 开始）：'),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: '表头行号'),
            keyboardType: TextInputType.number,
            onFieldSubmitted: (v) {
              final n = int.tryParse(v);
              onHeaderRowChanged(n != null && n > 0 ? n - 1 : null);
              onRetry();
            },
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  final int count;
  const _SuccessPanel({required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text('导入完成', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('成功写入 $count 条记录，作业类型已同步为表格列名'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

class _NonImportablePanel extends StatelessWidget {
  final ExcelParseResult result;
  const _NonImportablePanel(this.result);

  @override
  Widget build(BuildContext context) {
    final importableSheets = (result.sheetImportable ?? {})
        .entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('该工作表无可导入的绩效数据',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.hint ?? '请选择含「姓名 + 车数」的司机绩效表',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (importableSheets.isNotEmpty) ...[
              const Text('可切换到以下工作表导入：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...importableSheets.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(s)),
                    ],
                  ),
                ),
              ),
            ] else
              const Text('（文件中未检测到司机绩效表）'),
          ],
        ),
      ),
    );
  }
}

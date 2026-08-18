import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/job_types.dart';
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
          if (state.focusedWorker != null)
            SwitchListTile(
              title: Text('仅导入「${state.focusedWorker}」'),
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
                          ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              );
            })
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _HeaderRowTile extends StatefulWidget {
  final int headerRow;
  final int? headerOverride;
  final ValueChanged<int?> onChanged;
  const _HeaderRowTile(
      {required this.headerRow, required this.headerOverride, required this.onChanged});

  @override
  State<_HeaderRowTile> createState() => _HeaderRowTileState();
}

class _HeaderRowTileState extends State<_HeaderRowTile> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.headerOverride?.toString() ?? widget.headerRow.toString(),
    );
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _HeaderRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（重新解析/切换表头行）改变表头行时同步显示；用户正在编辑（聚焦）则不打断。
    if ((widget.headerOverride != oldWidget.headerOverride ||
            widget.headerRow != oldWidget.headerRow) &&
        !_focus.hasFocus) {
      _ctrl.text =
          widget.headerOverride?.toString() ?? widget.headerRow.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.format_list_numbered),
      title: Text(widget.headerOverride == null
          ? '表头行：第 ${widget.headerRow + 1} 行（自动识别）'
          : '表头行：第 ${widget.headerOverride! + 1} 行（手动）'),
      trailing: SizedBox(
        width: 70,
        child: TextFormField(
          controller: _ctrl,
          focusNode: _focus,
          decoration: const InputDecoration(labelText: '行号'),
          keyboardType: TextInputType.number,
          onFieldSubmitted: (v) {
            final n = int.tryParse(v);
            widget.onChanged(n != null && n > 0 ? n - 1 : null);
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
    final advancedJobCols = result.jobColumns
        .where((c) => DefaultJobTypes.advancedJobTypes.contains(c.name))
        .toList();
    final regularJobCols = result.jobColumns
        .where((c) => !DefaultJobTypes.advancedJobTypes.contains(c.name))
        .toList();
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
                if (result.overtimeCol != null)
                  Chip(
                    label: const Text('加班'),
                    avatar: const Icon(Icons.access_time),
                    backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                  ),
                ...regularJobCols.map((c) => Chip(
                      label: Text(c.price != null ? '${c.name}（¥${c.price}）' : c.name),
                      avatar: const Icon(Icons.build),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    )),
              ],
            ),
            if (advancedJobCols.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.tune),
                title: const Text('其他作业类型'),
                subtitle: Text(
                  '${advancedJobCols.map((c) => c.name).join('、')}（仅相关司机使用，点击展开）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                childrenPadding:
                    const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: advancedJobCols
                        .map((c) => Chip(
                              label: Text(c.price != null
                                  ? '${c.name}（¥${c.price}）'
                                  : c.name),
                              avatar: const Icon(Icons.build),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primaryContainer,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ],
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
                        style: TextStyle(
                            color: bad
                                ? Theme.of(context).colorScheme.error
                                : null)),
                    const SizedBox(width: 12),
                    Text('已选 $c',
                        style: TextStyle(
                          color: bad
                              ? Theme.of(context).colorScheme.error
                              : null,
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
    final focused = state.focusedWorker;
    // 统计同名出现次数，用于标注「同一人多次出现将合并统计」
    final nameCounts = <String, int>{};
    for (final r in result.rows) {
      nameCounts[r.workerName] = (nameCounts[r.workerName] ?? 0) + 1;
    }
    final hasDuplicateName = nameCounts.values.any((n) => n > 1);
    // 货场仅在「需要区分」时才逐行显示：单货场时只在顶部提示一次，无货场时完全不显示，
    // 避免 56 道等表格里每行都重复「货场 XX」造成界面凌乱。
    final yards = result.rows
        .where((r) => r.yard != null && r.yard!.isNotEmpty)
        .map((r) => r.yard!)
        .toSet();
    final showYardPerRow = yards.length > 1;
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
            if (hasDuplicateName)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '提示：同一人出现多行时（如挖掘机多船作业），导入后按船名分条记录，统计自动相加',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                ),
              ),
            const SizedBox(height: 4),
            if (yards.length == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Chip(
                  label: Text('货场：${yards.first}'),
                  avatar: const Icon(Icons.location_on),
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                ),
              ),
            ...result.rows.map((row) {
              final selected = state.selectedWorkers.contains(row.workerName);
              final disabled = state.enforceFixed &&
                  focused != null &&
                  row.workerName != focused;
              final dup = (nameCounts[row.workerName] ?? 0) > 1;
              final qty = row.quantities.entries
                  .map((e) => '${e.key}:${e.value}')
                  .join('  ');
              // 备注连同原样导入（表格里写了什么就带什么），预览如实反映落库内容。
              final detail = [
                if (showYardPerRow &&
                    row.yard != null &&
                    row.yard!.isNotEmpty)
                  '货场 ${row.yard}',
                if (row.vehicleNo.isNotEmpty) '车号 ${row.vehicleNo}',
                qty,
                if (row.remark != null && row.remark!.isNotEmpty)
                  '备注 ${row.remark}',
                if (dup) '同一人多船/多行，导入后按船分条、统计相加',
                if (disabled) '非默认姓名（关闭上方开关可导入）',
              ].where((s) => s.isNotEmpty).join('  ·  ');
              final hasBoat =
                  row.boatName != null && row.boatName!.isNotEmpty;
              return CheckboxListTile(
                value: selected,
                onChanged: disabled
                    ? null
                    : (v) => ref
                        .read(importProvider.notifier)
                        .toggleWorker(row.workerName, v ?? false),
                title: Text(row.workerName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (detail.isNotEmpty) Text(detail),
                    if (hasBoat)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Chip(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text('船名 ${row.boatName}'),
                          avatar: const Icon(Icons.directions_boat, size: 16),
                          backgroundColor:
                              Theme.of(context).colorScheme.secondaryContainer,
                        ),
                      ),
                  ],
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

class _ErrorPanel extends StatefulWidget {
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
  State<_ErrorPanel> createState() => _ErrorPanelState();
}

class _ErrorPanelState extends State<_ErrorPanel> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.headerRow != null ? (widget.headerRow! + 1).toString() : '',
    );
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ErrorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headerRow != oldWidget.headerRow && !_focus.hasFocus) {
      _ctrl.text =
          widget.headerRow != null ? (widget.headerRow! + 1).toString() : '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text('解析失败', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(widget.error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        const Text('若是表头行识别有误，可手动指定（填第几行，从 1 开始）：'),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          child: TextFormField(
            controller: _ctrl,
            focusNode: _focus,
            decoration: const InputDecoration(labelText: '表头行号'),
            keyboardType: TextInputType.number,
            onFieldSubmitted: (v) {
              final n = int.tryParse(v);
              widget.onHeaderRowChanged(n != null && n > 0 ? n - 1 : null);
              widget.onRetry();
            },
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: widget.onRetry, child: const Text('重试')),
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

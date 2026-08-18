import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/job_types.dart';
import '../../../core/constants/yards.dart';
import '../../../domain/entities/work_record.dart';
import '../../providers/history_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/selected_date_record_provider.dart';
import '../../widgets/job_type_card.dart';

/// 编辑历史记录页面：可修改姓名/车号/班次/作业数量/备注，保存回 Hive。
class EditRecordPage extends ConsumerStatefulWidget {
  final WorkRecord record;

  const EditRecordPage({super.key, required this.record});

  @override
  ConsumerState<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends ConsumerState<EditRecordPage> {
  late String _workerName;
  late String _vehicleNo;
  late String _boatName;
  late ShiftType _shift;
  late Map<String, int> _jobQuantities;
  late String _remark;
  late String? _yard;

  @override
  void initState() {
    super.initState();
    _workerName = widget.record.workerName;
    _vehicleNo = widget.record.vehicleNo;
    _boatName = widget.record.boatName ?? '';
    _shift = widget.record.shift;
    _jobQuantities = Map<String, int>.from(widget.record.jobQuantities);
    _remark = widget.record.remark ?? '';
    _yard = widget.record.yard;
  }

  @override
  Widget build(BuildContext context) {
    final unitPrices = ref.watch(unitPricesProvider);
    final jobTypes = unitPrices.keys.isNotEmpty
        ? unitPrices.keys.toList()
        : DefaultJobTypes.types;
    final totalQty = _jobQuantities.values.fold<int>(0, (a, b) => a + b);
    final totalAmount = _jobQuantities.entries.fold<double>(0, (sum, e) {
      return sum + (unitPrices[e.key] ?? 0) * e.value;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: () async {
              try {
                await _save();
              } catch (e) {
                if (!mounted) return;
                _showSaveError(e);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _workerName,
                  decoration: const InputDecoration(labelText: '姓名'),
                  onChanged: (v) => _workerName = v,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _vehicleNo,
                  decoration: const InputDecoration(labelText: '车号'),
                  onChanged: (v) => _vehicleNo = v,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _boatName,
                  decoration: const InputDecoration(labelText: '船名'),
                  onChanged: (v) => _boatName = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ShiftType>(
            segments: const [
              ButtonSegment(value: ShiftType.day, label: Text('白班')),
              ButtonSegment(value: ShiftType.night, label: Text('夜班')),
            ],
            selected: {_shift},
            onSelectionChanged: (s) => setState(() => _shift = s.first),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButtonFormField<String?>(
              value: _yard,
              decoration: const InputDecoration(labelText: '货场'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                    value: null, child: Text('未分类')),
                ...Yards.standardYards.map<DropdownMenuItem<String?>>(
                  (y) => DropdownMenuItem<String?>(value: y, child: Text(y)),
                ),
              ],
              onChanged: (v) => setState(() => _yard = v),
            ),
          ),
          const SizedBox(height: 16),
          Text('作业类型', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...jobTypes.map((jobType) => JobTypeCard(
                jobType: jobType,
                quantity: _jobQuantities[jobType] ?? 0,
                unitPrice: unitPrices[jobType] ?? 0,
                onChanged: (value) => setState(() {
                  _jobQuantities[jobType] = value.clamp(0, 9999);
                }),
              )),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _remark,
            decoration: const InputDecoration(labelText: '备注'),
            maxLines: 2,
            onChanged: (v) => _remark = v,
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '合计',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  Text(
                    '共 $totalQty 件 · ¥${totalAmount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSaveError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('保存失败：$e')),
    );
  }

  Future<void> _save() async {
    final updated = WorkRecord(
      id: widget.record.id,
      date: widget.record.date,
      workerName: _workerName,
      vehicleNo: _vehicleNo,
      shift: _shift,
      jobQuantities: _jobQuantities,
      remark: _remark,
      boatName: _boatName.isEmpty ? null : _boatName,
      yard: _yard,
    );
    // 按原 id 写入（导入记录 id 是 imp_日期_姓名，不能用按日期覆盖的 saveRecord，
    // 否则会覆盖同日「今日记账」并造成重复统计）。
    await ref.read(recordRepositoryProvider).putRecord(updated);
    if (!mounted) return;
    // 编辑保存后刷新全部记录相关 Provider，确保统计/今日摘要/近7天同步更新。
    // H2：失效全量快照根即可级联刷新所有派生 Provider。
    ref.invalidate(allRecordsProvider);
    ref.invalidate(selectedDateRecordProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存修改')),
    );
    Navigator.pop(context);
  }
}

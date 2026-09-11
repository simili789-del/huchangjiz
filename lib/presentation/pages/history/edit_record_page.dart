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
  /// 「加班」标记：勾选时并入备注『加班』（与 WorkRecord.isOvertime 判定一致）。
  late bool _overtime;

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
    _overtime = widget.record.isOvertime;
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
          const SizedBox(height: 8),
          // 「加班」开关：附加在白班/夜班之后，勾选时备注并入『加班』，
          // 与首页快速记账、明细页加班角标、统计页加班班次联动。
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _overtime,
              label: const Text('加班'),
              avatar: Icon(
                Icons.more_time,
                size: 18,
                color: _overtime ? Colors.white : Colors.red,
              ),
              selectedColor: Colors.red,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: _overtime ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (v) => setState(() => _overtime = v),
            ),
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
    // 「加班」开关并入备注（与 WorkRecord.isOvertime 判定、导入侧写法一致）：
    // 勾选 → 追加『加班』；取消 → 从备注移除，避免取消后残留旧标记。
    // 按分隔符切分后剔除『加班』片段再按需追加，
    // 避免简单 replaceAll 留下『叉车·』尾巴、反复编辑变成『叉车··加班』。
    final parts = _remark
        .split('·')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '加班')
        .toList();
    if (_overtime) parts.add('加班');
    final remark = parts.isEmpty ? null : parts.join('·');
    final updated = WorkRecord(
      id: widget.record.id,
      date: widget.record.date,
      workerName: _workerName,
      vehicleNo: _vehicleNo,
      shift: _shift,
      jobQuantities: _jobQuantities,
      remark: remark,
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/record_repository.dart';
import '../../domain/entities/work_record.dart';
import 'app_settings_provider.dart';
import 'history_provider.dart';
import 'repository_providers.dart';

/// 首页当前选中的记账日期。
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// 首页「上次作业详情」：取选中日期之前最近的一条记录。
///
/// H2 修复：改为从 [allRecordsProvider] 内存快照过滤，而非直接读 Hive。
/// invalidate(allRecordsProvider) 会自动级联失效本 Provider，
/// 消除写操作后需手写 invalidate 的脆弱失效链。
final lastRecordProvider = FutureProvider<WorkRecord?>((ref) async {
  final all = ref.watch(allRecordsProvider);
  final date = ref.watch(selectedDateProvider);
  final dayStart = DateTime(date.year, date.month, date.day);
  WorkRecord? latest;
  for (final r in all) {
    if (r.date.isBefore(dayStart)) {
      if (latest == null || r.date.isAfter(latest.date)) latest = r;
    }
  }
  return latest;
});

/// 根据选中日期加载/保存记录。
final selectedDateRecordProvider =
    StateNotifierProvider<SelectedDateRecordNotifier, AsyncValue<WorkRecord>>(
        (ref) {
  final repo = ref.watch(recordRepositoryProvider);
  return SelectedDateRecordNotifier(repo, ref);
});

class SelectedDateRecordNotifier
    extends StateNotifier<AsyncValue<WorkRecord>> {
  final RecordRepository _repository;
  final Ref _ref;

  SelectedDateRecordNotifier(this._repository, this._ref)
      : super(const AsyncLoading()) {
    reload();
  }

  /// 自动保存防抖：字段改动后 800ms 落盘一次，避免「只改内存没点保存」时
  /// App 被系统回收导致当日手填数据丢失。
  Timer? _saveDebounce;

  /// 表单记录是否含有实质内容（值得落库）。
  ///
  /// 车数任一 > 0、手填备注（剔除纯『加班』标记）、船名，三者其一即算。
  /// 纯『加班』标记不算实质内容：只勾了加班还没录车数就落库，会在明细页
  /// 留下「0车」垃圾条目（金额必为 0）。
  bool _hasSubstance(WorkRecord r) {
    if (r.jobQuantities.values.any((v) => v > 0)) return true;
    final remarkParts = (r.remark ?? '')
        .split('·')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '加班')
        .toList();
    if (remarkParts.isNotEmpty) return true;
    return (r.boatName ?? '').trim().isNotEmpty;
  }

  /// 字段改动后触发防抖落盘（不清除撤销栈，保留撤销能力）。
  ///
  /// 车数全 0 且无其他实质内容的表单不落库，反向删除当天表单记录——
  /// 顺带清掉此前版本误存的「0车」残留，也覆盖「把车数改回 0 =
  /// 想删掉这条」的操作意图。仅删表单自己的纯日期主键，
  /// imp_ 前缀的导入记录不受影响。
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      final cur = state.value;
      if (cur == null) return;
      if (_hasSubstance(cur)) {
        _repository.saveRecord(cur);
      } else {
        _repository.deleteFormRecord(cur.date);
      }
      // H2：只需失效全量快照根，所有派生 Provider（今日摘要/上次详情/明细/
      // 月报等）会级联失效，无需再手写一长串 invalidate。
      _ref.invalidate(allRecordsProvider);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  /// 表单编辑撤销栈：每次字段改动前压入改动前的快照，最多保留 50 步。
  final List<WorkRecord> _undoStack = [];

  /// 是否存在可撤销的编辑（供顶部栏撤销按钮判断是否启用）。
  bool get canUndo => _undoStack.isNotEmpty;

  /// 撤销最近一次表单编辑，恢复到上一个快照。
  void undo() {
    if (_undoStack.isEmpty) return;
    state = AsyncData(_undoStack.removeLast());
  }

  /// 字段改动前压入当前快照（草稿未加载时静默跳过）。
  void _pushUndo() {
    final current = state.value;
    if (current == null) return;
    _undoStack.add(current);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  DateTime get _date => _ref.read(selectedDateProvider);

  Future<void> reload() async {
    _saveDebounce?.cancel();
    _undoStack.clear();
    state = const AsyncLoading();
    try {
      final record = await _repository.getRecordByDate(_date);
      final defaults = _ref.read(appSettingsProvider);
      state = AsyncData(record.copyWith(
        workerName: record.workerName.isEmpty && defaults.defaultWorkerName.isNotEmpty
            ? defaults.defaultWorkerName
            : record.workerName,
        vehicleNo: record.vehicleNo.isEmpty && defaults.defaultVehicleNo.isNotEmpty
            ? defaults.defaultVehicleNo
            : record.vehicleNo,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void updateBasicInfo(
      {String? workerName,
      String? vehicleNo,
      ShiftType? shift,
      String? boatName}) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    state = AsyncData(current.copyWith(
      workerName: workerName,
      vehicleNo: vehicleNo,
      shift: shift,
      boatName: boatName,
    ));
    _scheduleSave();
  }

  /// 直接设置某作业类型的车数（键盘输入/微调用），内部 clamp 到 [0, 9999]。
  /// 与旧版的「增量」语义不同：此处传入的是「绝对值」。
  void updateJobQuantity(String jobType, int value) {
    final current = state.value;
    if (current == null) return;
    final v = value.clamp(0, 9999);
    if ((current.jobQuantities[jobType] ?? 0) == v) return;
    _pushUndo();
    final newQuantities = Map<String, int>.from(current.jobQuantities);
    newQuantities[jobType] = v;
    state = AsyncData(current.copyWith(jobQuantities: newQuantities));
    _scheduleSave();
  }

  /// 显式构造「仅备注不同」的新记录。
  ///
  /// 不能用 [WorkRecord.copyWith]：其 remark 参数是 `remark ?? this.remark`，
  /// 传 null 会被忽略、保留旧备注——这曾导致「取消加班」「清空备注」
  /// 两个操作看起来完全无效（点一下选中、再点取消，勾一直亮着）。
  /// 显式 new 才能让 remark=null 真正写进实体。
  WorkRecord _withRemark(WorkRecord r, String? remark) {
    return WorkRecord(
      id: r.id,
      date: r.date,
      workerName: r.workerName,
      vehicleNo: r.vehicleNo,
      shift: r.shift,
      jobQuantities: r.jobQuantities,
      remark: remark,
      boatName: r.boatName,
      yard: r.yard,
      overtime: r.overtime, // 显式构造须逐字段带上，漏了会丢加班标记
    );
  }

  void updateRemark(String remark) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    final t = remark.trim();
    state = AsyncData(_withRemark(current, t.isEmpty ? null : t));
    _scheduleSave();
  }

  /// 切换「加班」标记。
  ///
  /// 加班标记写在 [WorkRecord.overtime] 独立字段，**不再往备注里塞「加班」二字**——
  /// 否则备注里手填的「加班费另算」「晚上加班装车」这类内容会与标记纠缠不清：
  /// 判定用 contains（模糊）而删除只能匹配独立分段（精确），两套规则对不齐时
  /// 按钮就会「取消不掉」。独立字段后，备注随便填都不影响加班判定。
  ///
  /// 取消时额外清理历史遗留的独立「加班」分段（升级前的数据把标记写在备注里），
  /// 但只删恰好等于「加班」的分段，备注里的其他原话原样保留。
  void toggleOvertime(bool value) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    if (value) {
      state = AsyncData(current.copyWith(overtime: true));
    } else {
      final parts = (current.remark ?? '')
          .split('·')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e != '加班')
          .toList();
      final newRemark = parts.isEmpty ? null : parts.join('·');
      state = AsyncData(_withRemark(current, newRemark).copyWith(overtime: false));
    }
    _scheduleSave();
  }

  /// 一键复制昨日数据到当前选中日期。
  Future<void> copyYesterday() async {
    final yesterday = _date.subtract(const Duration(days: 1));
    final source = await _repository.getRecordByDate(yesterday);
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    state = AsyncData(current.copyWith(
      workerName: source.workerName,
      vehicleNo: source.vehicleNo,
      boatName: source.boatName,
      shift: source.shift,
      jobQuantities: Map<String, int>.from(source.jobQuantities),
    ));
    _scheduleSave();
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) return;
    // 与自动保存同一套判定：无实质内容（全 0 车且无备注/船名）不落库，
    // 反向删除，避免明细页残留「0车」记录。
    if (_hasSubstance(current)) {
      await _repository.saveRecord(current);
    } else {
      await _repository.deleteFormRecord(current.date);
    }
    _undoStack.clear();
    state = AsyncData(current);
    // H2：失效全量快照根即可，派生 Provider 自动级联刷新
    _ref.invalidate(allRecordsProvider);
  }
}

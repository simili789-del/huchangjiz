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

  /// 字段改动后触发防抖落盘（不清除撤销栈，保留撤销能力）。
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      final cur = state.value;
      if (cur == null) return;
      _repository.saveRecord(cur);
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

  void updateRemark(String remark) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    state = AsyncData(current.copyWith(remark: remark));
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
    await _repository.saveRecord(current);
    _undoStack.clear();
    state = AsyncData(current);
    // H2：失效全量快照根即可，派生 Provider 自动级联刷新
    _ref.invalidate(allRecordsProvider);
  }
}

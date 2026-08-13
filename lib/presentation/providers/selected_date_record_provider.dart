import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/record_repository.dart';
import '../../domain/entities/work_record.dart';
import 'app_settings_provider.dart';
import 'history_provider.dart';
import 'repository_providers.dart';
import 'stats_provider.dart';

/// 首页当前选中的记账日期。
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// 首页「上次作业详情」：取选中日期之前最近的一条记录。
final lastRecordProvider = FutureProvider<WorkRecord?>((ref) async {
  final repo = ref.watch(recordRepositoryProvider);
  final date = ref.watch(selectedDateProvider);
  return repo.getLatestBefore(date);
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
  }

  void updateJobQuantity(String jobType, int delta) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    final newQuantities = Map<String, int>.from(current.jobQuantities);
    newQuantities[jobType] =
        ((newQuantities[jobType] ?? 0) + delta).clamp(0, 9999);
    state = AsyncData(current.copyWith(jobQuantities: newQuantities));
  }

  void updateRemark(String remark) {
    final current = state.value;
    if (current == null) return;
    _pushUndo();
    state = AsyncData(current.copyWith(remark: remark));
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
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) return;
    await _repository.saveRecord(current);
    _undoStack.clear();
    state = AsyncData(current);
    // 刷新所有依赖记录的聚合 Provider，使首页摘要/统计/明细/上次详情立即更新
    _ref.invalidate(dayRecordsProvider);
    _ref.invalidate(monthlyStatsProvider);
    _ref.invalidate(historyRecordsProvider);
    _ref.invalidate(lastRecordProvider);
    _ref.invalidate(last7DaysSummaryProvider);
  }
}

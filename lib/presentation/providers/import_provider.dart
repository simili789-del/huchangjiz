import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/job_types.dart';
import '../../data/repositories/excel_importer.dart';
import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/work_record.dart';
import '../../domain/models/imported_row.dart';
import '../providers/history_provider.dart';
import '../providers/repository_providers.dart';
import '../providers/selected_date_record_provider.dart';
import '../providers/stats_provider.dart';

/// 导入向导的 UI 状态。
class ImportUiState {
  final String? filePath;
  final bool loading;
  final String? error;
  final ExcelParseResult? result;
  final Set<String> selectedWorkers;
  final DateTime? date;
  final ShiftType shift;
  final bool done;
  final int importedCount;

  /// 固定人员名单（来自设置），用于「强匹配」与名单外人员标注。
  final List<String> fixedWorkers;

  /// 强匹配开关：开启时只导入名单内人员，名单外的不可勾选。默认开。
  final bool enforceFixed;

  /// 是否匹配到历史模板（同格式表）。
  final bool templateMatched;

  /// 命中设置页「默认姓名」时的聚焦人员；非空时 UI 默认只勾他并强制仅导他。
  final String? focusedWorker;

  ImportUiState({
    this.filePath,
    this.loading = false,
    this.error,
    this.result,
    this.selectedWorkers = const {},
    this.date,
    this.shift = ShiftType.day,
    this.done = false,
    this.importedCount = 0,
    this.fixedWorkers = const [],
    this.enforceFixed = true,
    this.templateMatched = false,
    this.focusedWorker,
  });

  ImportUiState copyWith({
    String? filePath,
    bool? loading,
    String? error,
    ExcelParseResult? result,
    Set<String>? selectedWorkers,
    DateTime? date,
    ShiftType? shift,
    bool? done,
    int? importedCount,
    List<String>? fixedWorkers,
    bool? enforceFixed,
    bool? templateMatched,
    String? focusedWorker,
  }) {
    return ImportUiState(
      filePath: filePath ?? this.filePath,
      loading: loading ?? this.loading,
      error: error,
      result: result ?? this.result,
      selectedWorkers: selectedWorkers ?? this.selectedWorkers,
      date: date ?? this.date,
      shift: shift ?? this.shift,
      done: done ?? this.done,
      importedCount: importedCount ?? this.importedCount,
      fixedWorkers: fixedWorkers ?? this.fixedWorkers,
      enforceFixed: enforceFixed ?? this.enforceFixed,
      templateMatched: templateMatched ?? this.templateMatched,
      focusedWorker: focusedWorker ?? this.focusedWorker,
    );
  }
}

final importProvider =
    StateNotifierProvider<ImportNotifier, ImportUiState>((ref) {
  return ImportNotifier(ref);
});

class ImportNotifier extends StateNotifier<ImportUiState> {
  final Ref _ref;
  ImportNotifier(this._ref) : super(ImportUiState());

  Future<void> loadFile(String path,
      {String? sheetName, int? headerRow}) async {
    state = state.copyWith(
      filePath: path,
      loading: true,
      error: null,
      result: null,
      done: false,
      importedCount: 0,
    );
    try {
      final result = parseXlsx(path, sheetName: sheetName, headerRow: headerRow);
      // 归一化辅助：去除所有空白（含零宽/不可见字符），用于稳健匹配。
      String normalize(String s) =>
          s.replaceAll(RegExp(r'\s+'), '').replaceAll('　', '');

      final names = result.rows.map((r) => normalize(r.workerName)).toSet();
      final repo = _ref.read(settingsRepositoryProvider);
      final defaultName = normalize(repo.getAppSettings().defaultWorkerName);
      final fixed = repo.getFixedWorkers()
          .map((w) => normalize(w))
          .toList();
      final fixedSet = fixed.toSet();

      // 识别设置页「默认姓名」：命中则默认只勾该人并强制仅导他；
      // 否则回退到固定人员名单；再否则默认全选。
      // 匹配均使用归一化后的字符串，兼容 Excel 单元格含不可见字符/空格差异。
      String? focusedWorker;
      Set<String> selected;
      bool enforce;
      if (defaultName.isNotEmpty && names.contains(defaultName)) {
        focusedWorker = repo.getAppSettings().defaultWorkerName.trim();
        selected = {focusedWorker};
        enforce = true;
      } else if (fixedSet.isNotEmpty) {
        selected = names.intersection(fixedSet)
            .map((n) => _findOriginal(n, result.rows))
            .whereType<String>()
            .toSet();
        enforce = true;
      } else {
        selected = result.rows.map((r) => r.workerName).toSet();
        enforce = false;
      }

      // 模板匹配：同 sheet + 同原始列集合 视为同一格式表
      final tpl = repo.getImportTemplate();
      final fp = importTemplateFingerprint(result.sheetName, result.rawJobColumns);
      final matched = tpl != null &&
          importTemplateFingerprint(tpl.sheetName, tpl.rawColumns) == fp;
      state = state.copyWith(
        loading: false,
        result: result,
        selectedWorkers: selected,
        date: result.date,
        shift: result.shift,
        fixedWorkers: fixed,
        enforceFixed: enforce,
        focusedWorker: focusedWorker,
        templateMatched: matched,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void toggleWorker(String name, bool selected) {
    final s = <String>{...state.selectedWorkers};
    if (selected) {
      s.add(name);
    } else {
      s.remove(name);
    }
    state = state.copyWith(selectedWorkers: s);
  }

  void selectAll(bool all) {
    final s = all
        ? state.result?.rows.map((r) => r.workerName).toSet() ?? {}
        : <String>{};
    state = state.copyWith(selectedWorkers: s);
  }

  void setDate(DateTime d) => state = state.copyWith(date: d);
  void setShift(ShiftType s) => state = state.copyWith(shift: s);
  void setEnforceFixed(bool v) => state = state.copyWith(enforceFixed: v);

  /// 已勾选人员各作业类型车数求和（用于合计对账）。
  Map<String, int> get computedTotals {
    final totals = <String, int>{};
    final result = state.result;
    if (result == null) return totals;
    for (final row in result.rows) {
      if (!state.selectedWorkers.contains(row.workerName)) continue;
      for (final e in row.quantities.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
    }
    return totals;
  }

  /// 与表格合计行不一致的作业类型列名（差异=漏录/错录）。
  List<String> get mismatches {
    final result = state.result;
    if (result?.sheetTotals == null) return [];
    final computed = computedTotals;
    final miss = <String>[];
    result!.sheetTotals!.forEach((col, tableTotal) {
      final got = computed[col] ?? 0;
      if (got != tableTotal) miss.add(col);
    });
    return miss;
  }

  /// 确认导入：先同步作业类型（删旧的4个默认类 + 加表格清洗出的新类与单价），
  /// 再写入勾选人员的记录，最后保存固定人员名单。
  Future<void> confirm() async {
    final result = state.result;
    if (result == null) return;
    final date = state.date ?? DateTime.now();

    // 1) 同步作业类型
    final notifier = _ref.read(unitPricesProvider.notifier);
    final current = Map<String, double>.from(_ref.read(unitPricesProvider));
    for (final old in DefaultJobTypes.types) {
      if (current.containsKey(old)) notifier.remove(old);
    }
    for (final col in result.jobColumns) {
      final price = col.price ?? current[col.name] ?? 1.0;
      notifier.add(col.name, price);
    }

    // 2) 构造并写入记录
    final repo = _ref.read(recordRepositoryProvider);
    final settings = _ref.read(settingsRepositoryProvider);
    final fixedSet = state.enforceFixed
        ? settings.getFixedWorkers().toSet()
        : <String>{};
    final records = <WorkRecord>[];
    for (final row in result.rows) {
      if (!state.selectedWorkers.contains(row.workerName)) continue;
      // 强匹配：仅保留固定人员名单内的人（名单为空时等同于不过滤）
      if (state.enforceFixed && fixedSet.isNotEmpty) {
        if (!fixedSet.contains(row.workerName)) continue;
      }
      records.add(WorkRecord(
        id: RecordRepository.makeImportId(date, row.workerName),
        date: DateTime(date.year, date.month, date.day),
        workerName: row.workerName,
        vehicleNo: row.vehicleNo,
        shift: state.shift,
        jobQuantities: Map<String, int>.from(row.quantities),
        remark: row.remark,
        boatName: row.boatName,
      ));
    }
    await repo.saveImportedRecords(records);

    // 5) 刷新所有记录相关 Provider，让首页/明细页/月报页立刻反映新数据
    _ref.invalidate(historyRecordsProvider);
    _ref.invalidate(lastRecordProvider);
    _ref.invalidate(selectedDateRecordProvider);
    _ref.invalidate(last7DaysSummaryProvider);
    _ref.invalidate(monthlyStatsProvider);
    _ref.invalidate(dayRecordsProvider);

    // 3) 沉淀固定人员名单 + 刷新联动
    await settings.setFixedWorkers(state.selectedWorkers.toList());
    _ref.read(unitPricesProvider.notifier).refresh();

    // 4) 记忆本次表格模板（同格式表下次自动识别）
    await settings.saveImportTemplate(ImportTemplate(
      sheetName: result.sheetName,
      headerRow: result.headerRow,
      rawColumns: result.rawJobColumns,
    ));

    state = state.copyWith(done: true, importedCount: records.length);
  }

  /// 供 UI 在 confirm 完成后安全读取导入条数（避免越权访问 protected 的 state）。
  int get lastImportedCount => state.importedCount;

  void reset() => state = ImportUiState();

  /// 从归一化后的姓名在 rows 中找到原始 workerName（保留原始格式用于 selectedWorkers）。
  static String? _findOriginal(String normalized, List<ImportedRow> rows) {
    for (final r in rows) {
      if (r.workerName.replaceAll(RegExp(r'\s+'), '') == normalized) {
        return r.workerName;
      }
    }
    return null;
  }
}

/// 存放「微信/系统分享进来的待导入文件」路径；RootShell 监听后跳转向导并消费置空。
final sharedFileProvider = StateProvider<String?>((ref) => null);

/// 是否为可导入的表格文件（按扩展名过滤，因微信分享 MIME 常为 octet-stream）。
bool isImportableFile(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.xlsx') || p.endsWith('.xls') || p.endsWith('.csv');
}

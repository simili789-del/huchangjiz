import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/work_record.dart';
import 'repository_providers.dart';

enum QuickRange { today, last7Days, thisMonth, lastMonth, custom }

enum HistorySort { dateDesc, dateAsc, amountDesc }

class HistoryFilter {
  final QuickRange range;
  final String keyword;
  final ShiftType? shift;
  final DateTime? customStart;
  final DateTime? customEnd;
  final HistorySort sort;

  const HistoryFilter({
    this.range = QuickRange.last7Days,
    this.keyword = '',
    this.shift,
    this.customStart,
    this.customEnd,
    this.sort = HistorySort.dateDesc,
  });

  HistoryFilter copyWith({
    QuickRange? range,
    String? keyword,
    ShiftType? shift,
    DateTime? customStart,
    DateTime? customEnd,
    HistorySort? sort,
    bool clearShift = false,
  }) {
    return HistoryFilter(
      range: range ?? this.range,
      keyword: keyword ?? this.keyword,
      shift: clearShift ? null : (shift ?? this.shift),
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      sort: sort ?? this.sort,
    );
  }

  (DateTime, DateTime) resolveDates() {
    final now = DateTime.now();
    switch (range) {
      case QuickRange.today:
        return (now, now);
      case QuickRange.last7Days:
        return (now.subtract(const Duration(days: 6)), now);
      case QuickRange.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case QuickRange.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        final lastDay = DateTime(now.year, now.month, 0);
        return (lastMonth, lastDay);
      case QuickRange.custom:
        return (customStart ?? now, customEnd ?? now);
    }
  }
}

final historyFilterProvider =
    StateProvider<HistoryFilter>((ref) => const HistoryFilter());

final historyRecordsProvider = Provider<List<WorkRecord>>((ref) {
  final repository = ref.watch(recordRepositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final (start, end) = filter.resolveDates();
  var records = repository.query(
    start: start,
    end: end,
    keyword: filter.keyword,
    shift: filter.shift,
  );
  switch (filter.sort) {
    case HistorySort.dateDesc:
      records.sort((a, b) => b.date.compareTo(a.date));
    case HistorySort.dateAsc:
      records.sort((a, b) => a.date.compareTo(b.date));
    case HistorySort.amountDesc:
      records.sort((a, b) => b.amount({}).compareTo(a.amount({})));
  }
  return records;
});

/// 最近 7 天每日汇总，用于明细页顶部“近7天各类型车数”。
final last7DaysSummaryProvider = Provider<Map<DateTime, List<WorkRecord>>>((ref) {
  final repository = ref.watch(recordRepositoryProvider);
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 6));
  final records = repository.query(start: start, end: now);
  final map = <DateTime, List<WorkRecord>>{};
  for (final r in records) {
    final key = DateTime(r.date.year, r.date.month, r.date.day);
    map.putIfAbsent(key, () => []).add(r);
  }
  return map;
});

/// 某天的全部记录（含「今日记账」纯日期记录 + 当天所有 imp_ 导入记录），
/// 用于首页「今日摘要」聚合展示——导入当天数据后摘要同步更新。
final dayRecordsProvider =
    Provider.family<List<WorkRecord>, DateTime>((ref, date) {
  final repository = ref.watch(recordRepositoryProvider);
  final dayStart = DateTime(date.year, date.month, date.day);
  final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  return repository.query(start: dayStart, end: dayEnd);
});

/// 批量勾选待删除的记录 id 集合。
final selectedRecordIdsProvider = StateProvider<Set<String>>((ref) => {});

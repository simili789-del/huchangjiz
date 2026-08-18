import 'monthly_report.dart';

/// M2 自动对账结果。
class ReconciliationResult {
  final MonthlyReport report;
  final List<ReconciliationItem> items;
  final ReconciliationSummary summary;

  const ReconciliationResult({
    required this.report,
    required this.items,
    required this.summary,
  });
}

/// 对账差异类型。
enum DifferenceType {
  /// 月报与 App 完全一致。
  matched,

  /// 月报有车数，App 无记录或记录为 0。
  reportOnly,

  /// App 有车数，月报无/为 0。
  appOnly,

  /// 两边都有，但数量不一致。
  mismatch,
}

extension DifferenceTypeLabel on DifferenceType {
  String get label => switch (this) {
        DifferenceType.matched => '一致',
        DifferenceType.reportOnly => '月报独有',
        DifferenceType.appOnly => 'App 独有',
        DifferenceType.mismatch => '数量不符',
      };
}

/// 一条对账明细：某个 姓名+日期+班次+单价 维度的比对结果。
class ReconciliationItem {
  final String workerName;
  final int day;

  /// 班次：'早' / '晚'。
  final String shift;

  /// 单价（元/车）。
  final double price;

  /// 推断的作业类型（可能为空）。
  final String? jobType;

  /// 月报中的车数。
  final int reportCount;

  /// App 内汇总的车数。
  final int appCount;

  /// 差异类型。
  final DifferenceType type;

  const ReconciliationItem({
    required this.workerName,
    required this.day,
    required this.shift,
    required this.price,
    this.jobType,
    required this.reportCount,
    required this.appCount,
    required this.type,
  });
}

/// 对账汇总。
class ReconciliationSummary {
  final int matched;
  final int reportOnly;
  final int appOnly;
  final int mismatch;

  const ReconciliationSummary({
    this.matched = 0,
    this.reportOnly = 0,
    this.appOnly = 0,
    this.mismatch = 0,
  });

  int get total => matched + reportOnly + appOnly + mismatch;

  int get differenceCount => reportOnly + appOnly + mismatch;
}

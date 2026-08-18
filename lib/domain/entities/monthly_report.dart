/// 月度作业量汇总表：从 OCR 结果解析出的结构化月报。
class MonthlyReport {
  final int year;
  final int month;

  /// 每个人名下的各单价档次记录。
  final List<ReportEntry> entries;

  const MonthlyReport({
    required this.year,
    required this.month,
    required this.entries,
  });

  /// 当月总天数（用于校验空 cell）。
  int get daysInMonth {
    final first = DateTime(year, month, 1);
    final next = DateTime(year, month + 1, 1);
    return next.difference(first).inDays;
  }

  /// 所有人所有单价档的汇总车数。
  int get totalCars =>
      entries.fold(0, (sum, e) => sum + e.cells.fold(0, (s, c) => s + c.count));
}

/// 月报中「一个人 + 一个单价档次」的统计行。
class ReportEntry {
  final String workerName;

  /// 单价（元/车）。
  final double price;

  /// 根据单价推断出的作业类型（用于和 App 内记录对齐）。
  /// 若用户设置里多个作业类型同价，则取第一个；未匹配到为 null。
  final String? inferredJobType;

  /// 每日早/晚的车数格子。
  final List<ReportCell> cells;

  /// 月报最右「合计」列（若 OCR 未识别出则为 cells 求和）。
  final int total;

  const ReportEntry({
    required this.workerName,
    required this.price,
    this.inferredJobType,
    required this.cells,
    required this.total,
  });

  ReportEntry copyWith({
    String? workerName,
    double? price,
    String? inferredJobType,
    List<ReportCell>? cells,
    int? total,
  }) {
    return ReportEntry(
      workerName: workerName ?? this.workerName,
      price: price ?? this.price,
      inferredJobType: inferredJobType ?? this.inferredJobType,
      cells: cells ?? this.cells,
      total: total ?? this.total,
    );
  }
}

/// 月报中一个具体班次的车数。
class ReportCell {
  final int day;

  /// '早' 或 '晚'，对应 App 内 ShiftType.day / night。
  final String shift;

  /// 该车数，空单元格/未识别为 0。
  final int count;

  const ReportCell({
    required this.day,
    required this.shift,
    required this.count,
  });
}

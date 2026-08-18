import '../../domain/entities/monthly_report.dart';
import '../../domain/entities/reconciliation_result.dart';
import '../../domain/entities/work_record.dart';

/// M2 对账服务：把解析后的月报与 App 内手录记录按
/// 姓名 + 日期 + 班次 + 单价（推断作业类型）维度比对。
class ReconciliationService {
  /// 执行对账。
  ///
  /// [records] 应预先筛选为当月记录；[unitPrices] 为作业类型 → 单价。
  static ReconciliationResult reconcile(
    MonthlyReport report,
    List<WorkRecord> records,
    Map<String, double> unitPrices,
  ) {
    // 1. 反转单价映射：price -> jobType 列表（取第一个作为推断类型）。
    final priceToJobs = <double, List<String>>{};
    unitPrices.forEach((job, price) {
      priceToJobs.putIfAbsent(price, () => []).add(job);
    });

    // 2. 为 report entries 推断作业类型。
    final entriesWithJob = report.entries.map((e) {
      final jobs = priceToJobs[e.price] ?? [];
      return e.copyWith(inferredJobType: jobs.isEmpty ? null : jobs.first);
    }).toList();

    // 3. 按 (姓名, 日期, 班次, 作业类型) 汇总 App 车数。
    final appTotals = <_Key, int>{};
    for (final r in records) {
      final shiftLabel = r.shift.label == '夜班' ? '晚' : '早';
      for (final entry in r.jobQuantities.entries) {
        final job = entry.key;
        final qty = entry.value;
        final key = _Key(
          name: r.workerName,
          day: r.date.day,
          shift: shiftLabel,
          jobType: job,
        );
        appTotals[key] = (appTotals[key] ?? 0) + qty;
      }
    }

    // 4. 遍历月报每个 cell，与 App 汇总对比。
    final items = <ReconciliationItem>[];
    int matched = 0;
    int reportOnly = 0;
    int appOnly = 0;
    int mismatch = 0;

    for (final entry in entriesWithJob) {
      final jobType = entry.inferredJobType;
      for (final cell in entry.cells) {
        final key = _Key(
          name: entry.workerName,
          day: cell.day,
          shift: cell.shift,
          jobType: jobType ?? '',
        );
        final appCount = appTotals.remove(key) ?? 0;
        final reportCount = cell.count;

        DifferenceType type;
        if (reportCount == 0 && appCount == 0) {
          type = DifferenceType.matched;
          matched++;
        } else if (reportCount > 0 && appCount == 0) {
          type = DifferenceType.reportOnly;
          reportOnly++;
        } else if (reportCount == 0 && appCount > 0) {
          type = DifferenceType.appOnly;
          appOnly++;
        } else if (reportCount == appCount) {
          type = DifferenceType.matched;
          matched++;
        } else {
          type = DifferenceType.mismatch;
          mismatch++;
        }

        items.add(ReconciliationItem(
          workerName: entry.workerName,
          day: cell.day,
          shift: cell.shift,
          price: entry.price,
          jobType: jobType,
          reportCount: reportCount,
          appCount: appCount,
          type: type,
        ));
      }
    }

    // 5. 月报没覆盖、但 App 里有的记录（姓名不在月报中，或该人没有该单价档）。
    for (final key in appTotals.keys) {
      if (key.jobType.isEmpty) continue;
      final price = unitPrices[key.jobType] ?? 0;
      items.add(ReconciliationItem(
        workerName: key.name,
        day: key.day,
        shift: key.shift,
        price: price,
        jobType: key.jobType,
        reportCount: 0,
        appCount: appTotals[key]!,
        type: DifferenceType.appOnly,
      ));
      appOnly++;
    }

    // 按日期、人名排序，方便查看。
    items.sort((a, b) {
      final c = a.workerName.compareTo(b.workerName);
      if (c != 0) return c;
      if (a.day != b.day) return a.day.compareTo(b.day);
      return a.shift.compareTo(b.shift);
    });

    return ReconciliationResult(
      report: report,
      items: items,
      summary: ReconciliationSummary(
        matched: matched,
        reportOnly: reportOnly,
        appOnly: appOnly,
        mismatch: mismatch,
      ),
    );
  }
}

class _Key {
  final String name;
  final int day;
  final String shift;
  final String jobType;

  _Key({required this.name, required this.day, required this.shift, required this.jobType});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Key &&
          name == other.name &&
          day == other.day &&
          shift == other.shift &&
          jobType == other.jobType;

  @override
  int get hashCode => Object.hash(name, day, shift, jobType);
}

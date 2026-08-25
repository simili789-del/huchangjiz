import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/work_record.dart';
import 'history_provider.dart';
import 'repository_providers.dart';

class PriceGroup {
  final double price;
  final int totalQty;
  final int dayQty;
  final int nightQty;
  final List<String> jobTypes;

  /// 该单价下按日聚合的车数：日期 -> 车数。
  final Map<DateTime, int> qtyByDay;
  /// 该单价下按日聚合的白班车数。
  final Map<DateTime, int> dayQtyByDay;
  /// 该单价下按日聚合的夜班车数。
  final Map<DateTime, int> nightQtyByDay;

  const PriceGroup({
    required this.price,
    required this.totalQty,
    required this.dayQty,
    required this.nightQty,
    required this.jobTypes,
    required this.qtyByDay,
    required this.dayQtyByDay,
    required this.nightQtyByDay,
  });
}

class WorkerStat {
  final String name;
  final int totalQty;
  final int dayQty;
  final int nightQty;
  final double income;

  const WorkerStat({
    required this.name,
    required this.totalQty,
    required this.dayQty,
    required this.nightQty,
    required this.income,
  });
}

class MonthlyStats {
  final DateTime month;
  final Map<String, int> quantityByJobType;
  final Map<DateTime, int> vehicleCountByDay;
  final Map<String, double> incomeByWorker;
  final Map<double, PriceGroup> quantityByPrice;
  final List<WorkerStat> workerStats;
  final double totalIncome;
  final double estimatedSalary;
  final int totalDayQty;
  final int totalNightQty;

  /// 按货场（场地）聚合的作业总量：货场标准名（含空串「未分类」）-> 车数。
  final Map<String, int> quantityByYard;
  /// 按货场 × 作业类型 聚合：货场 -> (作业类型 -> 车数)，供「看清哪个货场干啥活」。
  final Map<String, Map<String, int>> qtyByYardJob;

  /// 按日聚合的加班记录数：日期 -> 加班记录条数（备注含『加班』即判加班）。
  final Map<DateTime, int> overtimeCountByDay;
  /// 按日聚合的加班班次：日期 -> 涉及班次集合（用于显示某天是白班/夜班加班）。
  final Map<DateTime, Set<ShiftType>> overtimeShiftsByDay;
  /// 当月加班记录总条数（即「加了几个班」）。
  final int totalOvertimeRecords;

  const MonthlyStats({
    required this.month,
    required this.quantityByJobType,
    required this.vehicleCountByDay,
    required this.incomeByWorker,
    required this.quantityByPrice,
    required this.workerStats,
    required this.totalIncome,
    required this.estimatedSalary,
    required this.totalDayQty,
    required this.totalNightQty,
    required this.quantityByYard,
    required this.qtyByYardJob,
    required this.overtimeCountByDay,
    required this.totalOvertimeRecords,
  });
}

final statsMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final statsWorkerFilterProvider = StateProvider<String>((ref) => '');

final monthlyStatsProvider = Provider<MonthlyStats>((ref) {
  final all = ref.watch(allRecordsProvider);
  final unitPrices = ref.watch(unitPricesProvider);
  final month = ref.watch(statsMonthProvider);
  final salary = ref.watch(salarySettingsProvider);
  final workerFilter = ref.watch(statsWorkerFilterProvider);

  final start = DateTime(month.year, month.month, 1);
  // 终点取当月最后一天 23:59:59.999，避免带时刻记录（如 JSON 恢复）被月末边界漏掉
  final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999, 999);
  // M9：复用全量快照，避免重复全量遍历 Hive。
  var records = all.where((r) {
    if (r.date.isBefore(start) || r.date.isAfter(end)) return false;
    return true;
  }).toList();

  if (workerFilter.isNotEmpty) {
    records = records
        .where((r) => r.workerName == workerFilter)
        .toList();
  }

  final quantityByJobType = <String, int>{};
  final vehicleCountByDay = <DateTime, int>{};
  final incomeByWorker = <String, double>{};
  final quantityByPrice = <double, PriceGroup>{};
  final workerTemp = <String, WorkerStat>{};
  final quantityByYard = <String, int>{};
  final qtyByYardJob = <String, Map<String, int>>{};
  double totalIncome = 0;
  int totalDayQty = 0;
  int totalNightQty = 0;
  final overtimeCountByDay = <DateTime, int>{};
  final overtimeShiftsByDay = <DateTime, Set<ShiftType>>{};
  int totalOvertimeRecords = 0;

  for (final r in records) {
    final amount = r.amount(unitPrices);
    final qty = r.jobQuantities.values.fold<int>(0, (a, b) => a + b);
    final dayKey = DateTime(r.date.year, r.date.month, r.date.day);
    final yard = r.yard ?? '';
    quantityByYard[yard] = (quantityByYard[yard] ?? 0) + qty;
    final yj = qtyByYardJob.putIfAbsent(yard, () => <String, int>{});
    r.jobQuantities.forEach((jt, q2) {
      yj[jt] = (yj[jt] ?? 0) + q2;
    });

    r.jobQuantities.forEach((jobType, q) {
      quantityByJobType[jobType] = (quantityByJobType[jobType] ?? 0) + q;

      final price = unitPrices[jobType] ?? 0;
      final existing = quantityByPrice[price];
      final dayAdd = r.shift == ShiftType.day ? q : 0;
      final nightAdd = r.shift == ShiftType.night ? q : 0;

      final qtyByDay = Map<DateTime, int>.from(existing?.qtyByDay ?? {});
      qtyByDay[dayKey] = (qtyByDay[dayKey] ?? 0) + q;
      final dayQtyByDay = Map<DateTime, int>.from(existing?.dayQtyByDay ?? {});
      if (dayAdd > 0) {
        dayQtyByDay[dayKey] = (dayQtyByDay[dayKey] ?? 0) + dayAdd;
      }
      final nightQtyByDay = Map<DateTime, int>.from(existing?.nightQtyByDay ?? {});
      if (nightAdd > 0) {
        nightQtyByDay[dayKey] = (nightQtyByDay[dayKey] ?? 0) + nightAdd;
      }

      quantityByPrice[price] = PriceGroup(
        price: price,
        totalQty: (existing?.totalQty ?? 0) + q,
        dayQty: (existing?.dayQty ?? 0) + dayAdd,
        nightQty: (existing?.nightQty ?? 0) + nightAdd,
        jobTypes: <String>{...(existing?.jobTypes ?? <String>[]), jobType}.toList(),
        qtyByDay: qtyByDay,
        dayQtyByDay: dayQtyByDay,
        nightQtyByDay: nightQtyByDay,
      );
    });

    vehicleCountByDay[dayKey] = (vehicleCountByDay[dayKey] ?? 0) + qty;
    incomeByWorker[r.workerName] = (incomeByWorker[r.workerName] ?? 0) + amount;
    totalIncome += amount;

    if (r.isOvertime) {
      overtimeCountByDay[dayKey] = (overtimeCountByDay[dayKey] ?? 0) + 1;
      overtimeShiftsByDay[dayKey] = (overtimeShiftsByDay[dayKey] ?? <ShiftType>{})..add(r.shift);
      totalOvertimeRecords += 1;
    }

    if (r.shift == ShiftType.day) {
      totalDayQty += qty;
    } else {
      totalNightQty += qty;
    }

    final ws = workerTemp[r.workerName];
    final dayQ = r.shift == ShiftType.day ? qty : 0;
    final nightQ = r.shift == ShiftType.night ? qty : 0;
    workerTemp[r.workerName] = WorkerStat(
      name: r.workerName,
      totalQty: (ws?.totalQty ?? 0) + qty,
      dayQty: (ws?.dayQty ?? 0) + dayQ,
      nightQty: (ws?.nightQty ?? 0) + nightQ,
      income: (ws?.income ?? 0) + amount,
    );
  }

  return MonthlyStats(
    month: month,
    quantityByJobType: quantityByJobType,
    vehicleCountByDay: vehicleCountByDay,
    incomeByWorker: incomeByWorker,
    quantityByPrice: quantityByPrice,
    workerStats: workerTemp.values.toList()
      ..sort((a, b) => b.totalQty.compareTo(a.totalQty)),
    totalIncome: totalIncome,
    estimatedSalary: salary.totalSalary(totalIncome),
    totalDayQty: totalDayQty,
    totalNightQty: totalNightQty,
    quantityByYard: quantityByYard,
    qtyByYardJob: qtyByYardJob,
    overtimeCountByDay: overtimeCountByDay,
    overtimeShiftsByDay: overtimeShiftsByDay,
    totalOvertimeRecords: totalOvertimeRecords,
  );
});

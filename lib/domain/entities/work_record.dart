import 'package:hive/hive.dart';

part 'work_record.g.dart';

/// 班次类型：白班 / 夜班
@HiveType(typeId: 1)
enum ShiftType {
  @HiveField(0)
  day,
  @HiveField(1)
  night,
}

extension ShiftTypeLabel on ShiftType {
  String get label => this == ShiftType.day ? '白班' : '夜班';
}

/// 单条“今日记账”记录。
///
/// 使用 hive_generator 自动生成 TypeAdapter，确保高性能序列化。
@HiveType(typeId: 0)
class WorkRecord extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final String workerName;

  @HiveField(3)
  final String vehicleNo;

  @HiveField(4)
  final ShiftType shift;

  @HiveField(5)
  final Map<String, int> jobQuantities; // 作业类型 -> 数量

  @HiveField(6)
  final String? remark;

  /// 船名（挖掘机绩效等场景的归属船，可选）。
  @HiveField(7)
  final String? boatName;

  WorkRecord({
    required this.id,
    required this.date,
    required this.workerName,
    required this.vehicleNo,
    required this.shift,
    required this.jobQuantities,
    this.remark,
    this.boatName,
  });

  WorkRecord copyWith({
    String? id,
    DateTime? date,
    String? workerName,
    String? vehicleNo,
    ShiftType? shift,
    Map<String, int>? jobQuantities,
    String? remark,
    String? boatName,
  }) {
    return WorkRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      workerName: workerName ?? this.workerName,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      shift: shift ?? this.shift,
      jobQuantities: jobQuantities ?? this.jobQuantities,
      remark: remark ?? this.remark,
      boatName: boatName ?? this.boatName,
    );
  }

  /// 依据单价配置计算当条记录金额。
  double amount(Map<String, double> unitPrices) {
    double total = 0;
    jobQuantities.forEach((jobType, qty) {
      total += (unitPrices[jobType] ?? 0) * qty;
    });
    return total;
  }
}

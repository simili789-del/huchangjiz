import 'package:hive/hive.dart';

part 'salary_settings.g.dart';

/// “设置管理”-> 工资构成：基本底薪 / 餐补 / 加班 / 工龄奖金 / 扣款。
@HiveType(typeId: 2)
class SalarySettings extends HiveObject {
  @HiveField(0)
  final double baseSalary;

  @HiveField(1)
  final double mealAllowance;

  @HiveField(2)
  final double deduction;

  @HiveField(3, defaultValue: 0)
  final double overtime;

  @HiveField(4, defaultValue: 0)
  final double seniorityBonus;

  SalarySettings({
    this.baseSalary = 0,
    this.mealAllowance = 0,
    this.deduction = 0,
    this.overtime = 0,
    this.seniorityBonus = 0,
  });

  SalarySettings copyWith({
    double? baseSalary,
    double? mealAllowance,
    double? deduction,
    double? overtime,
    double? seniorityBonus,
  }) {
    return SalarySettings(
      baseSalary: baseSalary ?? this.baseSalary,
      mealAllowance: mealAllowance ?? this.mealAllowance,
      deduction: deduction ?? this.deduction,
      overtime: overtime ?? this.overtime,
      seniorityBonus: seniorityBonus ?? this.seniorityBonus,
    );
  }

  /// 工资合计 = 计件收入 + 底薪 + 餐补 + 加班 + 工龄奖金 - 扣款。
  double totalSalary(double pieceIncome) {
    return pieceIncome + baseSalary + mealAllowance + overtime + seniorityBonus - deduction;
  }
}

import 'package:hive/hive.dart';

part 'app_settings.g.dart';

/// 全局应用设置：个人信息、目标车数、外观、数据备份相关配置。
@HiveType(typeId: 3)
class AppSettings extends HiveObject {
  @HiveField(0, defaultValue: '')
  final String defaultWorkerName;

  @HiveField(1, defaultValue: '')
  final String defaultVehicleNo;

  @HiveField(2, defaultValue: '45万货场')
  final String yardName;

  @HiveField(3, defaultValue: 100)
  final int dailyTargetVehicles;

  @HiveField(4, defaultValue: 2500)
  final int monthlyTargetVehicles;

  /// 主题色索引，对应 `AppTheme.primaries` 列表。
  @HiveField(5, defaultValue: 0)
  final int primaryColorIndex;

  @HiveField(6, defaultValue: false)
  final bool hideAmount;

  /// 船名库：设置页维护的船名名单（不与具体记录挂钩，仅作参考库）。
  @HiveField(7, defaultValue: <String>[])
  final List<String> boatNames;

  AppSettings({
    this.defaultWorkerName = '',
    this.defaultVehicleNo = '',
    this.yardName = '45万货场',
    this.dailyTargetVehicles = 100,
    this.monthlyTargetVehicles = 2500,
    this.primaryColorIndex = 0,
    this.hideAmount = false,
    this.boatNames = const [],
  });

  AppSettings copyWith({
    String? defaultWorkerName,
    String? defaultVehicleNo,
    String? yardName,
    int? dailyTargetVehicles,
    int? monthlyTargetVehicles,
    int? primaryColorIndex,
    bool? hideAmount,
    List<String>? boatNames,
  }) {
    return AppSettings(
      defaultWorkerName: defaultWorkerName ?? this.defaultWorkerName,
      defaultVehicleNo: defaultVehicleNo ?? this.defaultVehicleNo,
      yardName: yardName ?? this.yardName,
      dailyTargetVehicles: dailyTargetVehicles ?? this.dailyTargetVehicles,
      monthlyTargetVehicles: monthlyTargetVehicles ?? this.monthlyTargetVehicles,
      primaryColorIndex: primaryColorIndex ?? this.primaryColorIndex,
      hideAmount: hideAmount ?? this.hideAmount,
      boatNames: boatNames ?? this.boatNames,
    );
  }
}

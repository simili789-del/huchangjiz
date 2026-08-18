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

  /// 已解锁显示的非常用作业类型（其他作业类型）。默认空 → 首页不显示折叠区；
  /// 导入含某非常用类型或用户在「管理作业类型」里手动勾选时加入，持久化。
  @HiveField(8, defaultValue: <String>[])
  final List<String> revealedAdvancedTypes;

  /// 被隐藏的（普通/手动添加）作业类型。勾选取消即加入，首页常规区不再显示。
  /// 与 revealedAdvancedTypes 区分：后者管「其他作业类型」5 个固定高级类型的显隐，
  /// 本字段管其余可手动添加类型的显隐，二者互不干扰。
  @HiveField(9, defaultValue: <String>[])
  final List<String> hiddenJobTypes;

  AppSettings({
    this.defaultWorkerName = '',
    this.defaultVehicleNo = '',
    this.yardName = '45万货场',
    this.dailyTargetVehicles = 100,
    this.monthlyTargetVehicles = 2500,
    this.primaryColorIndex = 0,
    this.hideAmount = false,
    this.boatNames = const [],
    this.revealedAdvancedTypes = const [],
    this.hiddenJobTypes = const [],
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
    List<String>? revealedAdvancedTypes,
    List<String>? hiddenJobTypes,
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
      revealedAdvancedTypes:
          revealedAdvancedTypes ?? this.revealedAdvancedTypes,
      hiddenJobTypes: hiddenJobTypes ?? this.hiddenJobTypes,
    );
  }
}

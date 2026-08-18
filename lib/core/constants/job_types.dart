import 'package:flutter/material.dart';

/// 默认作业类型列表，用户可在“设置管理”中动态增删并配置单价。
class DefaultJobTypes {
  DefaultJobTypes._();

  static const List<String> types = [
    '货场装车',
    '货场归剁',
    '外倒装车',
    '内倒装车',
    '内倒归垛',
    '火车装车',
    '挖掘机加高',
    '神华装车',
    '神华归垛',
    '封垛',
  ];

  static const Map<String, double> defaultPrices = {
    '货场装车': 1.2,
    '货场归剁': 1.2,
    '外倒装车': 1.8,
    '内倒装车': 1.8,
    '内倒归垛': 1.2,
    '火车装车': 5.0,
    '挖掘机加高': 2.0,
    '神华装车': 1.2,
    '神华归垛': 1.2,
    '封垛': 2.0,
  };

  /// 非常用作业类型：仅少数司机 / 特殊货场才会用到，导入向导与首页「快速记账」
  /// 默认折叠隐藏（需要时点击展开），让常用界面保持清爽。
  /// - 火车装车：仅 56 道等少数司机
  /// - 神华装车 / 神华归垛：神华专区专用
  /// - 挖掘机加高 / 封垛：挖掘机作业类型
  static const Set<String> advancedJobTypes = {
    '火车装车',
    '神华装车',
    '神华归垛',
    '挖掘机加高',
    '封垛',
  };

  /// 作业类型展示色，用于卡片、图表、列表圆点。
  static const Map<String, Color> colors = {
    '货场装车': Colors.blue,
    '货场归剁': Colors.purple,
    '外倒装车': Colors.orange,
    '内倒装车': Colors.red,
    '内倒归垛': Colors.green,
    '火车装车': Colors.brown,
    '挖掘机加高': Colors.teal,
    '神华装车': Colors.indigo,
    '神华归垛': Colors.deepOrange,
    '封垛': Colors.cyan,
  };

  static Color colorOf(String jobType) {
    final predefined = colors[jobType];
    if (predefined != null) return predefined;
    // 超出预定义调色板的作业类型：按名称做确定性哈希生成稳定色相，
    // 保证不同作业类型颜色区分度高，且跨 App 重启保持一致
    // （不依赖 String.hashCode 的随机化，避免重启后颜色跳变）。
    var hash = 0;
    for (final rune in jobType.runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.5).toColor();
  }

  static double priceOf(String jobType) =>
      defaultPrices[jobType] ?? 1.0;
}

/// Hive Box 名称统一管理，避免魔法字符串散落各处。
class HiveBoxes {
  HiveBoxes._();

  static const String records = 'work_records_box';
  static const String jobPrices = 'job_prices_box';
  static const String salarySettings = 'salary_settings_box';
  static const String appSettings = 'app_settings_box';
  static const String appSettingsV2 = 'app_settings_v2_box';
}

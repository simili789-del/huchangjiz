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

  /// 货场（场地）。装载机/挖掘机绩效里按「区域标题 / 表标题 / 场地列 / 备注」识别，
  /// 同一司机同天可跨多个货场（各自独立记录，互不覆盖）。
  /// 老数据或首页手填无货场时为 null，统计时统一按「未分类」处理。
  @HiveField(8)
  final String? yard;

  /// 加班标记（新增字段，与备注解耦）。
  ///
  /// 早期版本把「加班」二字塞进备注来传递标记，导致：
  /// 判定用模糊匹配（remark 含『加班/加时/加班费』即算加班），
  /// 而取消按钮只删恰好等于『加班』的分段——两套规则对不齐，
  /// 备注写成「加班费另算」「晚上加班」这类非独立分段时就取消不掉。
  /// 现改为独立布尔字段：按钮/编辑页直接写 true/false，备注原样保留，
  /// 手填的「加班费另算」也不会被吞掉。
  ///
  /// null 表示老数据（Hive 无此字段），回退到备注文本推断，
  /// 保证升级前已保存的记录与导入记录行为不变。
  @HiveField(9)
  final bool? overtime;

  WorkRecord({
    required this.id,
    required this.date,
    required this.workerName,
    required this.vehicleNo,
    required this.shift,
    required this.jobQuantities,
    this.remark,
    this.boatName,
    this.yard,
    this.overtime,
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
    String? yard,
    bool? overtime,
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
      yard: yard ?? this.yard,
      overtime: overtime ?? this.overtime,
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

  /// 是否标记为「加班」：仅备注含「加班 / 加时 / 加班费」或单字「加」才判加班。
  /// 注意：「值班 / 值日 / 值」属于作业类型（与「叉车」并列），不在此判定内，
  /// 否则会与导入侧 exceL_importer 的作业类型归一（叉/叉车→叉车）冲突导致重复统计。
  /// 是否加班：优先读独立字段 [overtime]；老数据（null）回退到备注推断。
  ///
  /// 回退仅用于兼容升级前落库的记录与导入记录：那时还没有 overtime 字段，
  /// 加班信息就写在备注里。新写入的走独立字段，备注怎么填都不影响判定。
  bool get isOvertime {
    final o = overtime;
    if (o != null) return o;
    if (remark == null || remark!.isEmpty) return false;
    final r = remark!;
    return r.contains('加班') ||
        r.contains('加时') ||
        r.contains('加班费') ||
        r.trim() == '加';
  }
}

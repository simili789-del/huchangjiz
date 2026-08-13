/// Excel 导入过程中提取出的「单条人员车数」中间模型。
///
/// 与 [WorkRecord] 解耦：导入向导先解析出 [ImportedRow]，
/// 再由 provider 决定如何转成 [WorkRecord] 写入（含复合主键、作业类型同步）。
class ImportedRow {
  final String workerName;
  final String vehicleNo;
  final String? remark;
  final String? boatName; // 船名（挖掘机绩效等场景，可选；空即空，不继承）
  final Map<String, int> quantities; // 清洗后的作业类型名 -> 车数

  ImportedRow({
    required this.workerName,
    required this.vehicleNo,
    this.remark,
    this.boatName,
    required this.quantities,
  });
}

/// 表格里一个「作业类型列」清洗后的结果：
/// [name] 为干净作业类型名（已剥离「1.8元」尾巴），[price] 为提取出的单价（可能为 null）。
class CleanedColumn {
  final String name;
  final double? price;

  CleanedColumn(this.name, this.price);
}

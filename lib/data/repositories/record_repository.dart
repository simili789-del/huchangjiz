import 'package:hive/hive.dart';

import '../../core/constants/job_types.dart';
import '../../domain/entities/work_record.dart';

/// 记账数据仓库：向上层提供统一数据接口，屏蔽 Hive 存储细节。
class RecordRepository {
  Box<WorkRecord> get _box => Hive.box<WorkRecord>(HiveBoxes.records);

  /// 获取“今日”记录；若不存在则返回一条空白记录供表单编辑。
  Future<WorkRecord> getTodayRecord() async => getRecordByDate(DateTime.now());

  /// 获取指定日期记录；若不存在则返回空白草稿。
  Future<WorkRecord> getRecordByDate(DateTime date) async {
    final key = _dateKey(date);
    final existing = _box.get(key);
    if (existing != null) return existing;

    return WorkRecord(
      id: key,
      date: DateTime(date.year, date.month, date.day),
      workerName: '',
      vehicleNo: '',
      shift: ShiftType.day,
      jobQuantities: {},
    );
  }

  Future<void> saveRecord(WorkRecord record) async {
    await _box.put(_dateKey(record.date), record);
  }

  /// 批量写入导入记录。使用「imp_日期_姓名」复合主键，与「今日记账」的纯日期
  /// 主键空间隔离，多人同日互不覆盖；同一人同日重复导入即覆盖更新。
  Future<void> saveImportedRecords(List<WorkRecord> records) async {
    final map = <String, WorkRecord>{for (final r in records) r.id: r};
    await _box.putAll(map);
  }

  /// 生成导入记录的复合主键：imp_年-月-日_姓名。
  static String makeImportId(DateTime date, String name) {
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    return 'imp_${d}_$name';
  }

  Future<void> deleteRecords(List<String> ids) async {
    await _box.deleteAll(ids);
  }

  /// “复制昨日”：拉取昨日记录的作业数据，套用到今日草稿。
  Future<WorkRecord?> getYesterdayRecord() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return _box.get(_dateKey(yesterday));
  }

  /// 按日期范围 + 关键词（姓名/车号）查询明细。
  List<WorkRecord> query({
    DateTime? start,
    DateTime? end,
    String? keyword,
    ShiftType? shift,
  }) {
    return _box.values.where((r) {
      if (start != null && r.date.isBefore(start)) return false;
      if (end != null && r.date.isAfter(end)) return false;
      if (shift != null && r.shift != shift) return false;
      if (keyword != null && keyword.isNotEmpty) {
        final k = keyword.toLowerCase();
        if (!r.workerName.toLowerCase().contains(k) &&
            !r.vehicleNo.toLowerCase().contains(k) &&
            !(r.boatName?.toLowerCase().contains(k) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<WorkRecord> get all => _box.values.toList();

  /// 取指定日期之前「最近的一条」记录，用于首页展示上次作业详情。
  WorkRecord? getLatestBefore(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final list = _box.values
        .where((r) => r.date.isBefore(dayStart))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.isNotEmpty ? list.first : null;
  }

  /// 全部记录（供备份导出）。
  List<WorkRecord> getAllRecords() => _box.values.toList();

  /// 按 id 写入单条记录（导入 CSV 时逐条写入）。
  Future<void> putRecord(WorkRecord record) async =>
      _box.put(record.id, record);

  /// 用一批记录整体替换当前数据（从 JSON 备份恢复）。
  Future<void> replaceAllRecords(List<WorkRecord> records) async {
    await _box.clear();
    final map = <String, WorkRecord>{for (final r in records) r.id: r};
    await _box.putAll(map);
  }

  /// 清空全部记账记录。
  Future<void> clearAllRecords() async => _box.clear();

  /// 写入 3 条示例记录（当前月），便于初次体验。
  Future<void> seedSampleData() async {
    final now = DateTime.now();
    final samples = [
      _sample(now, 0, '张三', '鲁B12345', ShiftType.day, {'装车': 50, '卸车': 30}, '示例数据'),
      _sample(now, 1, '李四', '鲁B67890', ShiftType.night, {'倒短': 40}, '示例数据'),
      _sample(now, 2, '王五', '鲁B11111', ShiftType.day, {'归垛': 60}, '示例数据'),
    ];
    for (final s in samples) {
      await _box.put(s.id, s);
    }
  }

  WorkRecord _sample(
    DateTime now,
    int dayOffset,
    String name,
    String vehicle,
    ShiftType shift,
    Map<String, int> jobs,
    String remark,
  ) {
    final d = DateTime(now.year, now.month, now.day - dayOffset);
    final id =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return WorkRecord(
      id: id,
      date: d,
      workerName: name,
      vehicleNo: vehicle,
      shift: shift,
      jobQuantities: jobs,
      remark: remark,
    );
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

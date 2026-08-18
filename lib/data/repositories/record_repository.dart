import 'package:hive/hive.dart';

import '../../core/constants/job_types.dart';
import '../../core/constants/yards.dart';
import '../../domain/entities/work_record.dart';

/// 记账数据仓库：向上层提供统一数据接口，屏蔽 Hive 存储细节。
class RecordRepository {
  Box<WorkRecord> get _box => Hive.box<WorkRecord>(HiveBoxes.records);

  /// 判断键 [sk] 是否以 [base] 为「完整前缀」：整键相等，或下一个字符是 `_`
  /// 分隔符。防止 `name='张三'` 时误匹配 `imp_日期_张三丰_...` 这类同名前缀记录。
  bool _isBaseKey(String sk, String base) =>
      sk == base || sk.startsWith('${base}_');

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
  /// 主键空间隔离，多人同日互不覆盖；同一人同日重复出现（如挖掘机表同名多船、
  /// 多段合计）时自动合并车数、拼接备注，避免后写覆盖先写导致丢数。
  Future<void> saveImportedRecords(List<WorkRecord> records) async {
    final map = <String, WorkRecord>{};
    for (final r in records) {
      final existing = map[r.id];
      if (existing == null) {
        map[r.id] = r;
        continue;
      }
      // 同人同日多条：作业量累加，备注用「·」拼接，船名取第一条。
      final mergedQty = Map<String, int>.from(existing.jobQuantities);
      r.jobQuantities.forEach((k, v) => mergedQty[k] = (mergedQty[k] ?? 0) + v);
      final notes = <String>[
        if (existing.remark?.isNotEmpty == true) existing.remark!,
        if (r.remark?.isNotEmpty == true) r.remark!,
      ].join('·');
      map[r.id] = existing.copyWith(
        jobQuantities: mergedQty,
        remark: notes.isEmpty ? null : notes,
        boatName: existing.boatName ?? r.boatName,
      );
    }
    await _box.putAll(map);
  }

  /// 生成导入记录的复合主键：imp_年-月-日_姓名[_货场][_班次][_船名]。
  /// - 带船名时按船分条（挖掘机多船作业各存一条）；不带船名（铲车）按人一条。
  /// - 货场/班次纳入主键后，同一司机同天跨货场（如南货场+56道）、跨白班夜班
  ///   各自独立成记录，导入互不覆盖，统计可分别切分。
  static String makeImportId(DateTime date, String name,
      {String? yard, ShiftType? shift, String? boat}) {
    final d = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    final y = (yard != null && yard.isNotEmpty) ? '_$yard' : '';
    final s = shift != null ? '_${shift.label}' : '';
    final b = (boat != null && boat.isNotEmpty) ? '_$boat' : '';
    return 'imp_${d}_$name$y$s$b';
  }

  /// 删除某日期某人的导入记录。
  /// - 传入 [yard]/[shift] 时，仅删该（人+日+货场+班次）组合，避免误删同人同日
  ///   其他货场/班次的记录（多表导入不丢数）。
  /// - 无论是否传参，都会清理旧格式导入记录（`imp_日期_姓名` 裸主键，或
  ///   `imp_日期_姓名_船名` 单段且无货场/班次），防止升级前的数据与新课主键
  ///   共存导致重复计。
  /// 两类删除互不重叠（旧格式无货场/班次段，新格式有），用 Set 去重后一次性删除。
  Future<void> deleteImportedByWorker(DateTime date, String name,
      {String? yard, ShiftType? shift}) async {
    final base = 'imp_${_dateKey(date)}_$name';
    final keys = <String>{};
    // 1) 删人+日+货场+班次 组合前缀（不含船名段，船名分条交给写入时覆盖）。
    //    传入 yard/shift 时按组合精确删；都不传时删该人当天全部导入记录
    //    （新旧格式一并清除，用于「整人整日」移除场景）。
    if (yard != null || shift != null) {
      final y = (yard != null && yard.isNotEmpty) ? '_$yard' : '';
      final s = shift != null ? '_${shift.label}' : '';
      final comboPrefix = '$base$y$s';
      for (final k in _box.keys) {
        final sk = k.toString();
        if (sk.startsWith(comboPrefix)) keys.add(sk);
      }
    } else {
      for (final k in _box.keys) {
        final sk = k.toString();
        if (_isBaseKey(sk, base)) keys.add(sk);
      }
    }
    // 2) 旧格式兜底清理：升级前遗留的 imp_日期_姓名（裸）或
    //    imp_日期_姓名_船名（单段且无货场/班次）也要清掉，避免与新主键
    //    共存导致重复计。上面走「精确组合」分支时这条尤其必要；
    //    走「整人整日」分支时这些键已被 1) 覆盖，此处仅作去重不重复处理。
    for (final k in _box.keys) {
      final sk = k.toString();
      if (!_isBaseKey(sk, base)) continue;
      final rest = sk.substring(base.length);
      final segs = rest.split('_').where((x) => x.isNotEmpty).toList();
      if (segs.isEmpty) {
        keys.add(sk);
        continue;
      }
      if (segs.length == 1 &&
          !Yards.isStandard(segs[0]) &&
          segs[0] != '白班' &&
          segs[0] != '夜班') {
        keys.add(sk);
      }
    }
    if (keys.isNotEmpty) await _box.deleteAll(keys);
  }

  Future<void> deleteRecords(List<String> ids) async {
    await _box.deleteAll(ids);
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

  /// 全量记录在内存中的快照（供快照根 [allRecordsProvider] 使用）。
  /// L1 修复：与 [getAllRecords] 实现相同，改为委托，消除重复定义。
  List<WorkRecord> get all => getAllRecords();

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
  /// M3 修复：改用真实作业类型（货场装车/外倒装车/火车装车…），
  /// 避免金额全算 0、冒出"装车/卸车/倒短/归垛"等幽灵类型。
  Future<void> seedSampleData() async {
    final now = DateTime.now();
    final samples = [
      _sample(now, 0, '张三', '鲁B12345', ShiftType.day,
          {'货场装车': 50, '货场归剁': 20}, '示例数据'),
      _sample(now, 1, '李四', '鲁B67890', ShiftType.night,
          {'外倒装车': 30, '内倒装车': 25}, '示例数据'),
      _sample(now, 2, '王五', '鲁B11111', ShiftType.day,
          {'内倒归垛': 40, '火车装车': 5}, '示例数据'),
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

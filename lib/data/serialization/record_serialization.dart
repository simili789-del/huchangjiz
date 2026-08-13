import 'dart:convert';

import '../../domain/entities/work_record.dart';

/// 记账记录的序列化与反序列化。
///
/// - [toCsv] / 月报页「导出本月 CSV」：导出 CSV 文本。
/// - [toJson] / [fromJson]：JSON 备份的导出与恢复。兼容新旧两种字段命名：
///   新备份用 `workerName/vehicleNo/jobQuantities/remark`，
///   旧备份用 `name/car/counts/note`（见 [fromJson]）。
class RecordSerialization {
  RecordSerialization._();

  /// 导出为 CSV 文本。金额按当前单价配置实时计算（便于离线核对）。
  static String toCsv(List<WorkRecord> records, Map<String, double> unitPrices) {
    final buf = StringBuffer();
    buf.writeln([
      _csv('id'),
      _csv('日期'),
      _csv('姓名'),
      _csv('车号'),
      _csv('班次'),
      _csv('作业量'),
      _csv('金额'),
      _csv('备注'),
      _csv('船名'),
    ].join(','));

    for (final r in records) {
      final jobStr = r.jobQuantities.entries
          .where((e) => e.value != 0)
          .map((e) => '${e.key}:${e.value}')
          .join(';');
      buf.writeln([
        _csv(r.id),
        _csv(_dateStr(r.date)),
        _csv(r.workerName),
        _csv(r.vehicleNo),
        _csv(r.shift == ShiftType.day ? '白班' : '夜班'),
        _csv(jobStr),
        _csv(r.amount(unitPrices).toStringAsFixed(2)),
        _csv(r.remark ?? ''),
        _csv(r.boatName ?? ''),
      ].join(','));
    }
    return buf.toString();
  }

  /// 导出为 JSON 文本（可读、可经系统分享保存）。
  static String toJson(List<WorkRecord> records) {
    final list = records.map((r) => <String, dynamic>{
      'id': r.id,
      'date': r.date.toIso8601String(),
      'workerName': r.workerName,
      'vehicleNo': r.vehicleNo,
      'shift': r.shift == ShiftType.day ? 'day' : 'night',
      'jobQuantities': r.jobQuantities,
      'remark': r.remark,
      'boatName': r.boatName,
    }).toList();
    return jsonEncode({'version': 1, 'records': list});
  }

  /// 从 JSON 文本解析记录。容错：跳过缺日期的条目。
  static List<WorkRecord> fromJson(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    final raw = decoded is Map ? decoded['records'] : decoded;
    if (raw is! List) return [];

    final records = <WorkRecord>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final date = DateTime.tryParse(m['date']?.toString() ?? '');
      if (date == null) continue;

      final shift = m['shift'] == 'night' ? ShiftType.night : ShiftType.day;
      final jq = <String, int>{};
      // 兼容旧备份格式（字段名为 counts）与新格式（jobQuantities）。
      final rawJq = m['jobQuantities'] ?? m['counts'];
      if (rawJq is Map) {
        rawJq.forEach((k, v) => jq[k.toString()] = (v as num).toInt());
      }

      // 兼容旧备份字段名（name/car/note）与新字段名（workerName/vehicleNo/remark）。
      records.add(WorkRecord(
        id: m['id']?.toString() ??
            _makeId(date,
                m['workerName']?.toString() ?? m['name']?.toString() ?? ''),
        date: date,
        workerName: m['workerName']?.toString() ?? m['name']?.toString() ?? '',
        vehicleNo: m['vehicleNo']?.toString() ?? m['car']?.toString() ?? '',
        shift: shift,
        jobQuantities: jq,
        remark: m['remark']?.toString() ?? m['note']?.toString(),
        boatName: m['boatName']?.toString(),
      ));
    }
    return records;
  }

  static String _makeId(DateTime date, String name) {
    final d =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'imp_${d}_$name';
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _csv(String v) => '"${v.replaceAll('"', '""')}"';

}

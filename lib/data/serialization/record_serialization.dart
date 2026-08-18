import 'dart:convert';

import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/salary_settings.dart';
import '../../domain/entities/work_record.dart';

/// 全量备份包：记账记录 + 全部配置（单价/工资构成/应用设置/固定名单/导入模板）。
/// 导出时整体打包、恢复时整体写回，做到换机/重装后数据与配置零丢失。
class FullBackup {
  final List<WorkRecord> records;
  final Map<String, double>? jobPrices;
  final SalarySettings? salarySettings;
  final AppSettings? appSettings;
  final List<String>? fixedWorkers;
  final ImportTemplate? importTemplate;

  FullBackup({
    required this.records,
    this.jobPrices,
    this.salarySettings,
    this.appSettings,
    this.fixedWorkers,
    this.importTemplate,
  });

  /// 是否含有可恢复的配置项（用于 UI 提示与恢复逻辑分支）。
  bool get hasSettings =>
      jobPrices != null ||
      salarySettings != null ||
      appSettings != null ||
      fixedWorkers != null ||
      importTemplate != null;
}

/// 记账记录的序列化与反序列化。
///
/// - [toCsv] / 月报页「导出本月 CSV」：导出 CSV 文本。
/// - [toJson] / [fromJson]：仅记录的 JSON 备份（旧格式）。
/// - [toFullBackupJson] / [parseFullBackup]：记录 + 全部配置的全量备份。
///   解析兼容新旧两种字段命名：新备份用 `workerName/vehicleNo/jobQuantities/remark`，
///   旧备份用 `name/car/counts/note`。
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
      _csv('货场'),
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
        _csv(r.yard ?? ''),
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
      'yard': r.yard,
    }).toList();
    return jsonEncode({'version': 1, 'records': list});
  }

  /// 从 JSON 文本解析记录（旧格式，仅记录）。容错：跳过缺日期的条目。
  static List<WorkRecord> fromJson(String jsonStr) =>
      _parseRecords(_rawRecords(jsonDecode(jsonStr)));

  /// 从「记录数组或含 records 字段的对象」中取出记录原始列表。
  static dynamic _rawRecords(dynamic decoded) =>
      decoded is Map ? decoded['records'] : decoded;

  /// 把原始 JSON 列表解析为记录（容错缺日期、字段命名新旧兼容）。
  static List<WorkRecord> _parseRecords(dynamic raw) {
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
        // S2 加固：畸形备份里 jobQuantities 的值若写成字符串（如 "x"）而非数字，
        // 裸 `(v as num)` 会抛 CastError 冒泡到 UI 导致崩溃；改为类型判断后安全转换。
        rawJq.forEach((k, v) {
          if (v is num) jq[k.toString()] = v.toInt();
        });
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
        yard: m['yard']?.toString(),
      ));
    }
    return records;
  }

  /// 构造全量备份的可序列化结构（记录 + 全部配置：单价/工资构成/应用设置/
  /// 固定名单/导入模板）。恢复时整包写回，做到「换机零风险」。
  /// 抽出为独立方法，便于在主线程廉价构造后交给 compute 做 jsonEncode（L2）。
  static Map<String, dynamic> fullBackupPayload(FullBackup backup) {
    final settings = <String, dynamic>{};
    if (backup.jobPrices != null) settings['jobPrices'] = backup.jobPrices;
    if (backup.salarySettings != null) {
      final s = backup.salarySettings!;
      settings['salarySettings'] = {
        'baseSalary': s.baseSalary,
        'mealAllowance': s.mealAllowance,
        'deduction': s.deduction,
        'overtime': s.overtime,
        'seniorityBonus': s.seniorityBonus,
      };
    }
    if (backup.appSettings != null) {
      final a = backup.appSettings!;
      settings['appSettings'] = {
        'defaultWorkerName': a.defaultWorkerName,
        'defaultVehicleNo': a.defaultVehicleNo,
        'yardName': a.yardName,
        'dailyTargetVehicles': a.dailyTargetVehicles,
        'monthlyTargetVehicles': a.monthlyTargetVehicles,
        'primaryColorIndex': a.primaryColorIndex,
        'hideAmount': a.hideAmount,
        'boatNames': a.boatNames,
      };
    }
    if (backup.fixedWorkers != null) settings['fixedWorkers'] = backup.fixedWorkers;
    if (backup.importTemplate != null) {
      settings['importTemplate'] = backup.importTemplate!.toJson();
    }
    final recordList = backup.records.map((r) => <String, dynamic>{
      'id': r.id,
      'date': r.date.toIso8601String(),
      'workerName': r.workerName,
      'vehicleNo': r.vehicleNo,
      'shift': r.shift == ShiftType.day ? 'day' : 'night',
      'jobQuantities': r.jobQuantities,
      'remark': r.remark,
      'boatName': r.boatName,
      'yard': r.yard,
    }).toList();
    return {'version': 2, 'records': recordList, 'settings': settings};
  }

  /// 导出全量备份 JSON 文本（供同步调用场景）。同等逻辑见 [fullBackupPayload]。
  static String toFullBackupJson(FullBackup backup) =>
      jsonEncode(fullBackupPayload(backup));

  /// 解析全量备份 JSON。兼容旧版（只有 records 或无 settings 字段）。
  static FullBackup parseFullBackup(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      // 极旧格式：整文件就是一个记录数组
      return FullBackup(records: _parseRecords(decoded));
    }
    final records = _parseRecords(decoded['records']);
    final settingsRaw = decoded['settings'];
    final settings = settingsRaw is Map
        ? Map<String, dynamic>.from(settingsRaw)
        : <String, dynamic>{};

    Map<String, double>? jobPrices;
    if (settings['jobPrices'] is Map) {
      jobPrices = {};
      (settings['jobPrices'] as Map?)?.forEach((k, v) {
        jobPrices![k.toString()] = (v as num?)?.toDouble() ?? 0;
      });
    }

    SalarySettings? salarySettings;
    if (settings['salarySettings'] is Map) {
      final s = Map<String, dynamic>.from(settings['salarySettings'] as Map);
      salarySettings = SalarySettings(
        baseSalary: (s['baseSalary'] as num?)?.toDouble() ?? 0,
        mealAllowance: (s['mealAllowance'] as num?)?.toDouble() ?? 0,
        deduction: (s['deduction'] as num?)?.toDouble() ?? 0,
        overtime: (s['overtime'] as num?)?.toDouble() ?? 0,
        seniorityBonus: (s['seniorityBonus'] as num?)?.toDouble() ?? 0,
      );
    }

    AppSettings? appSettings;
    if (settings['appSettings'] is Map) {
      final a = Map<String, dynamic>.from(settings['appSettings'] as Map);
      appSettings = AppSettings(
        defaultWorkerName: a['defaultWorkerName'] as String? ?? '',
        defaultVehicleNo: a['defaultVehicleNo'] as String? ?? '',
        yardName: a['yardName'] as String? ?? '45万货场',
        dailyTargetVehicles: a['dailyTargetVehicles'] as int? ?? 100,
        monthlyTargetVehicles: a['monthlyTargetVehicles'] as int? ?? 2500,
        primaryColorIndex: a['primaryColorIndex'] as int? ?? 0,
        hideAmount: a['hideAmount'] as bool? ?? false,
        boatNames: (a['boatNames'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
    }

    List<String>? fixedWorkers;
    if (settings['fixedWorkers'] is List) {
      fixedWorkers =
          (settings['fixedWorkers'] as List).map((e) => e.toString()).toList();
    }

    ImportTemplate? importTemplate;
    if (settings['importTemplate'] is Map) {
      try {
        importTemplate = ImportTemplate.fromJson(
            Map<String, dynamic>.from(settings['importTemplate'] as Map));
      } catch (_) {
        importTemplate = null;
      }
    }

    return FullBackup(
      records: records,
      jobPrices: jobPrices,
      salarySettings: salarySettings,
      appSettings: appSettings,
      fixedWorkers: fixedWorkers,
      importTemplate: importTemplate,
    );
  }

  static String _makeId(DateTime date, String name) {
    final d =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'imp_${d}_$name';
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _csv(String v) {
    var s = v.replaceAll('"', '""');
    if (RegExp(r'^[=+\-@]').hasMatch(s)) s = " $s";
    return '"$s"';
  }

}

/// 顶层函数：把已构造好的备份 payload 序列化为 JSON 字符串。
/// 供 compute 在独立 isolate 中执行，避免多年数据构造超大 JSON 时阻塞主线程（L2）。
String jsonEncodePayload(Map<String, dynamic> payload) => jsonEncode(payload);

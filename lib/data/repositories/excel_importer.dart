import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel2003/excel2003.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../domain/entities/work_record.dart';
import '../../domain/models/imported_row.dart';
import '../../core/constants/yards.dart';

/// 解析后的表头结构：姓名/车号/备注/船名/日期/班次/加班 列的位置，
/// 以及作业类型列（列号 -> 归一后的 [CleanedColumn]）。
///
/// 同一工作表内常叠放多张结构不同的子表（如「南货场绩效」「56道货场绩效表」），
/// 行解析阶段靠此结构逐行提取；遇到结构不同的新表头行会切换为新的 [_HeaderInfo]。
class _HeaderInfo {
  final int? nameCol;
  final int? vehCol;
  final int? remarkCol;
  /// 备注兜底列：当表头「备注」列右侧紧跟一个无表头的空列、
  /// 且用户常把备注填在那一格时（备注列错位一格），此列作为备注的兜底来源。
  final int? remarkFallbackCol;
  final int? boatCol;
  final int? dateCol;
  final int? shiftCol;
  final int? overtimeCol;
  /// 货场（场地）列：表内显式「场地/货场/区域」列时，逐行取该列值作为本行货场。
  final int? yardCol;
  final Map<int, CleanedColumn> jobCols;
  final Map<int, String> rawJobCols;

  /// 作业类型归一名集合，用于判断「新子表头」与「分页重复表头」。
  final Set<String> jobNames;

  int get maxCol {
    var m = nameCol ?? -1;
    for (final c in [vehCol, remarkCol, boatCol, dateCol, shiftCol, overtimeCol, yardCol, remarkFallbackCol]) {
      if (c != null && c > m) m = c;
    }
    for (final c in jobCols.keys) {
      if (c > m) m = c;
    }
    return m;
  }

  _HeaderInfo({
    required this.nameCol,
    this.vehCol,
    this.remarkCol,
    this.remarkFallbackCol,
    this.boatCol,
    this.dateCol,
    this.shiftCol,
    this.overtimeCol,
    this.yardCol,
    required this.jobCols,
    required this.rawJobCols,
  }) : jobNames = jobCols.values.map((c) => c.name).toSet();
}

/// 解析 xlsx/xls 的一次性结果，供导入向导直接使用。
class ExcelParseResult {
  final List<String> sheetNames;
  final String sheetName;
  final int headerRow;
  final int? nameCol;
  final int? vehCol;
  final int? remarkCol;
  /// 加班列（如「加班」「加」「加班时长」），其值记为每条记录的备注，不当作车数。
  final int? overtimeCol;
  final List<CleanedColumn> jobColumns;
  final List<ImportedRow> rows;
  final DateTime? date;
  final ShiftType shift;

  /// 整表识别出的默认货场（取自表/区域标题或 sheet 名）；多区域表为首个区域货场。
  /// 仅作 UI 兜底展示，逐行货场以 [ImportedRow.yard] 为准。
  final String? yard;

  /// 船名列（可选；挖掘机绩效表的船名常在表头为空的 A 列）。
  final int? boatCol;

  /// 该表是否为可导入的司机绩效表。false 时 [hint] 说明原因，UI 应提示换表。
  final bool importable;

  /// 不可导入原因（importable 为 false 时非空）。
  final String? hint;

  /// 文件内每个工作表是否可导入（供向导下拉标注）。
  final Map<String, bool>? sheetImportable;

  /// 清洗前的原始作业类型列名（用于「模板记忆」指纹匹配）。
  final List<String> rawJobColumns;

  /// 表格里的「合计」行（清洗后列名 -> 车数合计），作为导入对账基准。
  /// 没有合计行时为 null。
  final Map<String, int>? sheetTotals;

  ExcelParseResult({
    required this.sheetNames,
    required this.sheetName,
    required this.headerRow,
    this.nameCol,
    this.vehCol,
    this.remarkCol,
    this.overtimeCol,
    this.boatCol,
    required this.jobColumns,
    required this.rows,
    this.date,
    required this.shift,
    this.yard,
    this.rawJobColumns = const [],
    this.sheetTotals,
    this.importable = true,
    this.hint,
    this.sheetImportable,
  });
}

/// 解析 xlsx/xls：定位表头行 → 清洗作业类型列名（剥离「1.8元」单价）→
/// 跳过合计/标题行 → 提取每个人各作业类型车数，并解析班次与日期。
///
/// [sheetName] 不传则自动选中首个「看起来像司机绩效表」的工作表；
/// [headerRow] 不传则自动扫描含「姓名」的行。
ExcelParseResult parseXlsx(String path, {String? sheetName, int? headerRow}) {
  final bytes = File(path).readAsBytesSync();
  // M5 防护：拒绝超大文件，避免把整文件读进内存后 OOM / 主线程长时间阻塞。
  const maxBytes = 50 * 1024 * 1024; // 50MB
  if (bytes.length > maxBytes) {
    throw Exception('文件过大（>50MB），已拒绝解析以防内存溢出');
  }
  final lower = path.toLowerCase();

  // 主路径：spreadsheet_decoder（快速、功能全，但不支持批注/复杂格式）
  _RawWorkbook raw;
  if (lower.endsWith('.xls')) {
    // 旧版 Excel 97-2003（BIFF8），微信/WPS 分享仍常见
    raw = _fromExcel2003(bytes);
  } else {
    try {
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      raw = _fromSpreadsheetDecoder(decoder);
    } on UnsupportedError {
      // Fallback：纯 Dart ZIP+XML 解析（兼容含批注/drawings/超大 styles 的 xlsx）
      raw = _fallbackDecodeBytes(bytes);
    }
  }

  final sheetNames = raw.tables.keys.toList();

  // 预扫描每个 sheet 是否可导入（供向导下拉标注，并用于默认 sheet 选择）
  final sheetImportableMap = _scanImportableRaw(raw);
  // 用户未指定 sheet、或指定的 sheet 不存在时，自动选中首个「看起来像司机
  // 绩效表」的 sheet（含 绩效/铲车/装载机/挖掘机 关键词优先，且非考勤类）。
  var target = sheetName;
  if (target == null || !raw.tables.containsKey(target)) {
    target = _pickDefaultSheetRaw(raw) ?? sheetNames.first;
  }
  final table = raw.tables[target];
  if (table == null) {
    throw Exception('未找到工作表「$target」，可用：${sheetNames.join('、')}');
  }
  final rows = table.rows;

  // 1) 定位表头行
  int headerIdx;
  if (headerRow != null) {
    headerIdx = headerRow;
  } else {
    headerIdx =
        rows.indexWhere((r) => r.any((c) => _text(c)?.contains('姓名') ?? false));
    if (headerIdx < 0) {
      throw Exception('未找到表头（包含「姓名」的行），请手动指定表头行');
    }
  }
  if (headerIdx >= rows.length) {
    throw Exception('表头行 $headerIdx 超出表格范围');
  }

  // 2) 归类列：把表头行解析为结构化列信息（姓名/车号/备注/船名/日期/班次/作业列）。
  //    同一工作表内常叠放多张结构不同的子表（如「南货场绩效」「56道货场绩效表」），
  //    行解析阶段遇到结构不同的新表头行会自动切换列映射（见下方行循环）。
  final firstHeader = rows[headerIdx];
  var header = _analyzeHeader(firstHeader);
  // 货场识别：默认以表/区域标题或 sheet 名为整表货场（sheetYard）；
  // 行循环遇新子表头（如下半区「56道货场绩效表」）时按区域标题更新 currentYard，
  // 使同一张表上下两个货场的记录各自归属正确，统计不串。
  var currentYard = _detectSheetYard(target, rows, headerIdx);
  final sheetYard = currentYard;
  // 收集所有子表的作业类型（按归一名去重），供结果 jobColumns 与「同步作业类型」使用。
  final effectiveJobCols = <CleanedColumn>[...header.jobCols.values];
  final rawJobColumnsForResult = header.rawJobCols.values.toList();
  if (header.nameCol == null) {
    // 找不到精确的「姓名」列：该表大概率不是司机绩效表，温柔返回而非抛异常，
    // 让向导提示用户切换到含「姓名」列的绩效表。
    return ExcelParseResult(
      importable: false,
      hint: '未找到「姓名」列，该表不是司机绩效表（司机绩效表需含「姓名」列）',
      sheetNames: sheetNames,
      sheetName: target,
      headerRow: headerIdx < 0 ? 0 : headerIdx,
      jobColumns: const [],
      rows: const [],
      shift: ShiftType.day,
      yard: null,
      sheetImportable: sheetImportableMap,
    );
  }
  // 挖掘机模式：存在「船名」列时，船名即作业类型（逐行向上延续填充），
  // 其余数值列（jobCols）作为该车名的车数。
  var isExcavator = header.boatCol != null;

  // 3) 解析班次与日期（取自表头上一行的 meta 行；逐单元格，支持 Excel 序列日期）
  DateTime? date;
  var shift = ShiftType.day;
  if (headerIdx - 1 >= 0) {
    for (final c in rows[headerIdx - 1]) {
      final t = _text(c) ?? '';
      if (t.contains('夜')) {
        shift = ShiftType.night;
      } else if (t.contains('白')) {
        shift = ShiftType.day;
      }
      final d = _parseDateCell(c);
      if (d != null) date = d;
    }
  }

  // 4) 逐行提取人员车数；空姓名行是「合计行/说明行/空行」，需区分
  final result = <ImportedRow>[];
  String? lastBoat; // 挖掘机表船名常合并单元格留空，向上延续
  Map<String, int>? sheetTotals;
  for (int r = headerIdx + 1; r < rows.length; r++) {
    // 稀疏行补齐：补齐到「当前生效表头」的最大列，避免 rows[r][col] 越界。
    // 同一 sheet 内不同子表表头宽度不同（如 56道 8 列 vs 南货场 7 列），
    // 故按当前 header 补齐，每次切换子表头后自动适配新宽度。
    final need = header.maxCol + 1;
    if (rows[r].length < need) {
      rows[r] = [
        ...rows[r],
        ...List.filled(need - rows[r].length, ''),
      ];
    }

    // 归一化姓名/船名内部空白（如「玛蒂尔 达」→「玛蒂尔达」），
    // 同时去除全角空格与零宽字符（Excel 复制粘贴常带入）。
    final nameC = header.nameCol;
    final name = (nameC == null ? '' : _text(rows[r][nameC]) ?? '')
        .replaceAll(RegExp(r'[\s\u00A0\u200B\u200C\u200D\ufeff]'), '')
        .replaceAll('　', '');
    // 表头行（当前姓名列值为「姓名」）：可能是「分页重复表头」或「新子表头」。
    // 把该行当表头重新解析，若作业列名集合与当前表头不同则为新子表，
    // 切换列映射后继续；否则视为分页表头直接跳过。两者都不当作数据行。
    if (name == '姓名') {
      final cand = _analyzeHeader(rows[r]);
      if (cand.nameCol != null && _isDifferentHeader(cand, header)) {
        header = cand;
        isExcavator = header.boatCol != null;
        for (final c in header.jobCols.values) {
          if (!effectiveJobCols.any((e) => e.name == c.name)) {
            effectiveJobCols.add(c);
          }
        }
        // 切换到新子表头：向上扫描区域标题（如「56道货场绩效表」）更新货场归属。
        final regionYard = _detectRegionYard(rows, r);
        if (regionYard != null) currentYard = regionYard;
      }
      continue;
    }

    // 本行生效表头已稳定（表头行已 continue），缓存列索引到局部变量，
    // 便于 Dart 对 int? 做 null 提升（getter 不能在条件/三元表达式中自动提升为 int）。
    final vehC = header.vehCol;
    final remarkC = header.remarkCol;
    final boatC = header.boatCol;
    final rowBoat = boatC != null
        ? (_text(rows[r][boatC]) ?? '').replaceAll(RegExp(r'\s+'), '')
        : null;

    // 日期 / 班次列优先于表头 meta 行（显式列存在时逐行覆盖）
    final dateC = header.dateCol;
    if (dateC != null) {
      final d = _parseDateCell(rows[r][dateC]);
      if (d != null) date = d;
    }
    final shiftC = header.shiftCol;
    if (shiftC != null) {
      final s = _text(rows[r][shiftC]) ?? '';
      if (s.contains('夜')) {
        shift = ShiftType.night;
      } else if (s.contains('白')) {
        shift = ShiftType.day;
      }
    }

    if (name.isEmpty) {
      // 合计/小计行：姓名列为空但作业列有值。司机绩效表每行都有姓名，
      // 故姓名列为空时若带车数即为合计行（如本表把「合计」写在车号列，姓名列留空）；
      // 若无车数则是空行，直接跳过。
      final hasJob = header.jobCols.keys.any((c) => (_toInt(rows[r][c]) ?? 0) > 0) ||
          (header.boatCol != null &&
              (rowBoat?.isNotEmpty ?? false) &&
              header.jobCols.keys.any((c) => (_toInt(rows[r][c]) ?? 0) > 0));
      if (hasJob) {
        final totals = <String, int>{};
        for (final e in header.jobCols.entries) {
          final v = _toInt(rows[r][e.key]);
          if (v != null && v > 0) {
            totals[e.value.name] = (totals[e.value.name] ?? 0) + v;
          }
        }
        if (header.boatCol != null && (rowBoat?.isNotEmpty ?? false)) {
          final sum = header.jobCols.keys
              .map((c) => _toInt(rows[r][c]) ?? 0)
              .fold(0, (a, b) => a + b);
          if (sum > 0) totals[rowBoat!] = sum;
        }
        if (totals.isNotEmpty) sheetTotals = _mergeTotals(sheetTotals, totals);
      }
      continue;
    }
    if (name.contains('制表')) continue;
    if (name.contains('合计')) {
      final totals = <String, int>{};
      for (final e in header.jobCols.entries) {
        final v = _toInt(rows[r][e.key]);
        if (v != null && v > 0) totals[e.value.name] = v;
      }
      if (header.boatCol != null && (rowBoat?.isNotEmpty ?? false)) {
        final sum = header.jobCols.keys
            .map((c) => _toInt(rows[r][c]) ?? 0)
            .fold(0, (a, b) => a + b);
        if (sum > 0) totals[rowBoat!] = sum;
      }
      if (totals.isNotEmpty) sheetTotals = _mergeTotals(sheetTotals, totals);
      continue;
    }

    // 姓名列为纯数字（如「1050.0」）不是真实司机姓名（多为误填的车号），
    // 跳过以免把车数挂到一个假人员上污染人员库。
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(name)) continue;

    // 货场归属：区域标题（currentYard）为默认；若本表有「场地」列则取列值；
    // 否则若本行备注含货场关键字（如挖掘机「五六道」卸船）则用备注货场。
    String? rowYard = currentYard;
    final yardColIdx = header.yardCol;
    if (yardColIdx != null) {
      final yc = Yards.canonicalYard(_text(rows[r][yardColIdx]) ?? '');
      if (yc != null) rowYard = yc;
    } else if (remarkC != null) {
      final rc = Yards.canonicalYard(_text(rows[r][remarkC]) ?? '');
      if (rc != null) rowYard = rc;
    }

    if (isExcavator) {
      // 挖掘机模式：列名含「加高」→ 作业类型 = 挖掘机加高；
      // 列名含「封垛/封跺（米）」→ 作业类型 = 封垛（米数即车数，按车算钱），
      // 列识别阶段已放行该列，会进入 jobCols 参与车数统计。
      // 船名记入备注（方便追溯挖了哪条船），车数取各作业类型列之和。
      if (rowBoat != null && rowBoat.isNotEmpty) lastBoat = rowBoat;
      final bt = (rowBoat != null && rowBoat.isNotEmpty) ? rowBoat : lastBoat;
      final quantities = <String, int>{};
      for (final e in header.jobCols.entries) {
        final q = _toInt(rows[r][e.key]) ?? 0;
        if (q > 0) {
          quantities[e.value.name] = (quantities[e.value.name] ?? 0) + q;
        }
      }
      if (quantities.isEmpty) continue;
      // 船名写入 boatName 字段（按船分条记录，统计时自动相加），备注只保留原始备注。
      // 同时把「加班」列的值并入备注，与 OCR 对账方案"备注含『加班』即判加班"一致。
      final remark = _mergeOvertimeRemark(
        _readRemark(rows[r], remarkC, header.remarkFallbackCol),
        _readOvertime(rows[r], header.overtimeCol),
      );
      result.add(ImportedRow(
        workerName: name,
        vehicleNo: vehC != null ? _formatVehicleNo(rows[r][vehC]) : '',
        remark: remark,
        boatName: (bt != null && bt.isNotEmpty) ? bt : null,
        quantities: quantities,
        yard: rowYard,
        shift: shift.name,
      ));
    } else {
      // 铲车模式：各作业类型列的车数（同名标准类型跨列累加，
      // 例如「汽出」「汽提」「装车」都归一为「货场装车」时需求和）
      final quantities = <String, int>{};
      for (final e in header.jobCols.entries) {
        final q = _toInt(rows[r][e.key]) ?? 0;
        if (q > 0) quantities[e.value.name] = (quantities[e.value.name] ?? 0) + q;
      }
      if (quantities.isEmpty) continue;
      // 把「加班」列的值并入备注，与 OCR 对账方案"备注含『加班』即判加班"一致。
      final remark = _mergeOvertimeRemark(
        _readRemark(rows[r], remarkC, header.remarkFallbackCol),
        _readOvertime(rows[r], header.overtimeCol),
      );
      result.add(ImportedRow(
        workerName: name,
        vehicleNo: vehC != null ? _formatVehicleNo(rows[r][vehC]) : '',
        remark: remark,
        boatName: (rowBoat != null && rowBoat.isNotEmpty) ? rowBoat : null,
        quantities: quantities,
        yard: rowYard,
        shift: shift.name,
      ));
    }
  }

  // 作业类型列：挖掘机表和铲车表都用各子表 jobCols 的归一结果（已在行循环中累积）。

  // 非绩效表（考勤/工资/汇总/火车明细等）或完全无车数 → 标记为不可导入，
  // 让向导提示用户切换工作表，避免把考勤表当成绩效表污染工资数据。
  // 整表是否绩效表以首个表头（firstHeader）判断，符合「按第一个表头识别整表」的预期。
  if (_isNonPerfSheet(target, firstHeader) || result.isEmpty) {
    final reason = _isNonPerfSheet(target, firstHeader)
        ? '该表疑似考勤/工资/汇总/火车明细表，不是司机绩效表。请选择含「姓名 + 车数」的绩效表（如铲车/装载机/挖掘机绩效）'
        : '未在该表识别到任何车数数据';
    return ExcelParseResult(
      importable: false,
      hint: reason,
      sheetNames: sheetNames,
      sheetName: target,
      headerRow: headerIdx,
      nameCol: header.nameCol,
      vehCol: header.vehCol,
      remarkCol: header.remarkCol,
      boatCol: header.boatCol,
      overtimeCol: header.overtimeCol,
        jobColumns: effectiveJobCols,
        rows: result,
        date: date,
        shift: shift,
        yard: sheetYard,
        rawJobColumns: rawJobColumnsForResult,
        sheetTotals: sheetTotals,
        sheetImportable: sheetImportableMap,
      );
  }

  return ExcelParseResult(
    sheetNames: sheetNames,
    sheetName: target,
    headerRow: headerIdx,
    nameCol: header.nameCol,
    vehCol: header.vehCol,
    remarkCol: header.remarkCol,
    boatCol: header.boatCol,
    jobColumns: effectiveJobCols,
    rows: result,
    date: date,
    shift: shift,
    yard: sheetYard,
    rawJobColumns: rawJobColumnsForResult,
    sheetTotals: sheetTotals,
    sheetImportable: sheetImportableMap,
  );
}

/// 在独立 isolate 中解析 xlsx（compute 入口），避免大文件解析阻塞主线程（M5）。
/// 参数用单值记录包裹，满足 compute 的「单一消息」约束。
ExcelParseResult parseXlsxInIsolate((String, String?, int?) args) =>
    parseXlsx(args.$1, sheetName: args.$2, headerRow: args.$3);

/// 判断表头/表名是否像「考勤/工资/汇总/火车明细」等非绩效表。
/// 依据：表名含排除关键词、列数过多（>25）、或候选作业列中纯数字/序号列过半
/// （考勤表的 1~31 日列）。作业类型列通常为中文业务词（装车/归垛/倒货/加高）。
bool _isNonPerfSheet(String sheetName, List<dynamic> headerCells) {
  const excluded = [
    '考勤',
    '工资',
    '汇总',
    '报表',
    '火车',
    '明细',
    '56道',
    '班表',
    '作业量',
    '出勤', // 出勤/准驾车型/有效期 等花名册不是司机绩效表
  ];
  for (final k in excluded) {
    if (sheetName.contains(k)) return true;
  }
  if (headerCells.length > 25) return true;
  int total = 0;
  int numeric = 0;
  for (int c = 0; c < headerCells.length; c++) {
    final h = _text(headerCells[c]) ?? '';
    if (h.isEmpty) continue;
    if (h == '姓名' ||
        h == '车号' ||
        h.contains('车牌') ||
        h.contains('车辆') ||
        h.contains('备注') ||
        h.contains('说明') ||
        h.contains('船名') ||
        h.contains('船号') ||
        h.contains('日期') ||
        h.contains('时间') ||
        h.contains('班次') ||
        h.contains('白班') ||
        h.contains('夜班') ||
        h.contains('班别') ||
        h.contains('签字') ||
        h.contains('签名') ||
        h.contains('复核') ||
        h.contains('确认') ||
        (h.contains('米') &&
            !h.contains('封垛') &&
            !h.contains('封跺')) ||
        h.contains('吨') ||
        h.contains('方') ||
        h.contains('准驾') ||
        h.contains('车型') ||
        h.contains('有效期') ||
        h.contains('驾照')) {
      continue;
    }
    total++;
    if (h == '序号' ||
        RegExp(r'^\d+$').hasMatch(h) ||
        RegExp(r'^\d+\.\d+$').hasMatch(h)) {
      numeric++;
    }
  }
  if (total > 0 && numeric * 2 >= total) return true;
  return false;
}

/// 取出单元格底层值（文本/数字/公式缓存值）。
/// spreadsheet_decoder 返回的 rows 里每个元素已经是原始值，无需额外 unwrap。
dynamic _raw(dynamic cell) => cell;

String? _text(dynamic cell) {
  final v = _raw(cell);
  if (v == null) return null;
  return v.toString().trim();
}

/// 车号（车牌号）规整：Excel 常以浮点存储整数车号（如 119.0），
/// 直接 toString 会得到 "119.0" 这种带小数尾巴的串，需去掉。
/// 规则：整数型数值 → 取整字符串（119.0 → 119）；保留字母与混合文本
/// （如 "京A12345" 不受影响）；数值文本 "119.0" → "119"。
String _formatVehicleNo(dynamic cell) {
  final v = _raw(cell);
  if (v == null) return '';
  if (v is double) {
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }
  final s = v.toString().trim();
  if (s.isEmpty) return '';
  return s.replaceFirst(RegExp(r'\.0+$'), '');
}

int? _toInt(dynamic cell) {
  final v = _raw(cell);
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    // 仅接受纯数字表达式（数字与 + - . / 及空白），拒绝「C6场1000吨」之类
    // 带中文/字母的注释文本，否则会把其中的数字误算成车数。
    if (!RegExp(r'^[\d\s+\-.,/]+$').hasMatch(s)) return null;
    // 支持『56+49』『5+101』之类的车数表达式：提取所有数字求和取整。
    // 挖掘机绩效表常在「加高（车）」列手写多段合计。
    final nums = RegExp(r'-?\d+(?:\.\d+)?').allMatches(s);
    if (nums.isEmpty) return null;
    var sum = 0;
    for (final m in nums) {
      sum += (double.tryParse(m.group(0)!) ?? 0).round();
    }
    return sum;
  }
  return null;
}

/// 解析日期单元格：兼容 Excel 序列日期（如 46240）、2026/8/12、
/// 2026-08-12、2026年8月12日、2026年-8/6 等写法。
DateTime? _parseDateCell(dynamic cell) {
  // spreadsheet_decoder 可能已把日期单元格转成 DateTime
  if (cell is DateTime) return cell;
  // Excel 序列日期（数字）：基准 1899-12-30
  if (cell is int || cell is double) {
    final n = (cell as num).toDouble();
    if (n > 20000 && n < 80000) {
      return DateTime(1899, 12, 30).add(Duration(days: n.round()));
    }
    return null;
  }
  final v = (cell?.toString() ?? '').trim();
  if (v.isEmpty) return null;
  // 2026-08-12 / 2026/8/12
  final slash = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(v);
  if (slash != null) {
    return DateTime(
      int.parse(slash.group(1)!),
      int.parse(slash.group(2)!),
      int.parse(slash.group(3)!),
    );
  }
  // 2026.8.3 / 2026.8. 3（点分隔，部分表用「年月日」之外的点格式）
  final dot =
      RegExp(r'(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})').firstMatch(v);
  if (dot != null) {
    return DateTime(
      int.parse(dot.group(1)!),
      int.parse(dot.group(2)!),
      int.parse(dot.group(3)!),
    );
  }
  // 2026年8月12日 / 2026年08月10号（口语「号」同「日」）
  final cn =
      RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]').firstMatch(v);
  if (cn != null) {
    return DateTime(
      int.parse(cn.group(1)!),
      int.parse(cn.group(2)!),
      int.parse(cn.group(3)!),
    );
  }
  // 2026年-8/6 或 2026年8/6（混合分隔符）
  final mix =
      RegExp(r'(\d{4})\s*年[^\d]*(\d{1,2})[^\d]*(\d{1,2})').firstMatch(v);
  if (mix != null) {
    return DateTime(
      int.parse(mix.group(1)!),
      int.parse(mix.group(2)!),
      int.parse(mix.group(3)!),
    );
  }
  return DateTime.tryParse(v.replaceAll('/', '-'));
}

/// 把表格里的作业类型列名归一为系统标准类型。
/// 归一规则（用户指定）：
///   含「节数」 → 火车装车
///   归垛 / 归剁 / 货场归剁 / 货场归垛 → 货场归剁
///   内倒归剁 / 内倒归垛 → 内倒归垛
///   汽出 / 汽提 / 装车 / 车数 / 汽提装车 / 货场装车 → 货场装车
///   外倒装车 / 倒货 / 外倒倒货 / 倒货装车 → 外倒装车
///   内倒 / 内倒装车（含「端货」后缀） → 内倒装车
///   神华装车 → 神华装车（独立作业类型，不并入货场装车）
///   神华归垛 / 神华归剁 → 神华归垛（独立作业类型，不并入货场归剁）
///   封垛 / 封跺（米） → 封垛（挖掘机作业类型，米数即车数，按车算钱）
/// 价格歧义消解：单纯「装车」若单价 ≈ 1.8 则视为「外倒装车」（1.2 则为「货场装车」）。
/// 预处理：先剥离结尾的价格后缀（「(1.8)」「1.8元」「/1.8」「，端货1.8元」等），
/// 再做字面归一，避免价格写法干扰匹配。
String _canonicalJobType(String name, {double? price}) {
  if (name.contains('节数')) return '火车装车';

  // 预处理：去掉常见价格后缀，保留核心名称
  // 「汽提装车(1.2)」→「汽提装车」；「内倒装车，端货1.8元」→「内倒装车」
  var core = name;
  // 去掉括号及内容：仅当括号在末尾且内含数字时
  core = core.replaceAll(RegExp(r'[（(]\s*\d+(?:\.\d+)?\s*元?\s*[)）]\s*$'), '');
  // 去掉结尾「数字 元?」：数字前可有 逗号/空格/斜杠 分隔（如「内倒/1.8」），
  // 也可直接连写在汉字后（如「内倒1.8」「内倒1.8元」），避免名字+数字被当成新类型。
  core = core.replaceAll(RegExp(r'(?:[，,\s/]|(?<=\D))\s*\d+(?:\.\d+)?\s*元?\s*$'), '');
  // 去掉结尾「，端货」「/端货」等子类型修饰
  core = core.replaceAll(RegExp(r'[，,\s/]\s*端货\s*$'), '');
  core = core.trim();

  // 价格歧义消解：单纯「装车」根据单价区分
  // 1.8 元的「装车」= 外倒装车；1.2 元（或无价）的「装车」= 货场装车
  if (core == '装车' && price != null && (price - 1.8).abs() < 0.01) {
    return '外倒装车';
  }

  // 字面归一
  switch (core) {
    case '归垛':
    case '归剁':
    case '货场归剁':
    case '货场归垛':
      return '货场归剁';
    case '内倒归剁':
    case '内倒归垛':
      return '内倒归垛';
    case '汽出':
    case '汽提':
    case '装车':
    case '车数':
    case '汽提装车':
    case '货场装车':
      return '货场装车';
    case '外倒装车':
    case '倒货':
    case '倒货装车':
    case '外倒倒货':
    case '货场倒货':
      return '外倒装车';
    case '内倒':
    case '内倒装车':
      return '内倒装车';
  }
  // 挖掘机加高：含「加高」的列名（如「加高（车）」）→ 挖掘机加高
  if (core.contains('加高')) return '挖掘机加高';
  // 端货：铲车作业中的端货作业，归入内倒装车（端货是内倒装车的一种）
  if (core == '端货') return '内倒装车';
  // 神华系列：作为独立作业类型，不并入货场装车/货场归剁。
  // 神华装车→神华装车；神华归垛/神华归剁→神华归垛。
  if (core.contains('神华')) {
    if (core.contains('装车')) return '神华装车';
    if (core.contains('归')) return '神华归垛';
  }
  // 挖掘机封垛（米）：米数即车数（按车算钱），作为独立作业类型 封垛。
  // （列识别阶段已对「封垛/封跺（米）」放行，不再按米数列过滤丢弃。）
  if (core.contains('封垛') || core.contains('封跺')) return '封垛';
  // 模糊兜底：core 含某些关键字时也归一
  if (core.contains('归垛') || core.contains('归剁')) {
    if (core.contains('内倒')) return '内倒归垛';
    return '货场归剁';
  }
  if (core.contains('汽提') || core.contains('汽出')) return '货场装车';
  if (core.contains('倒货') || core.contains('外倒')) return '外倒装车';
  if (core == '内倒' || core.contains('内倒装车')) return '内倒装车';
  return core;
}

/// 清洗备注：统一「叉车」写法。
/// 表格里常写「叉」「叉车」（可能带空格/全角空格），导入后统一记为「叉车」。
String? _cleanRemark(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  // 归一化空白后精确判断「叉」/「叉车」；其他备注原样保留。
  final normalized = t.replaceAll(RegExp(r'[\s\u00A0\u200B\u200C\u200D\ufeff]'), '')
      .replaceAll('　', '');
  if (normalized == '叉' || normalized == '叉车') return '叉车';
  return raw;
}

/// 读取某行备注：优先取对齐的备注列 [remarkCol]；若该列为空，
/// 且 [fallbackCol]（备注列右侧紧邻的无表头空列）有非空文本，
/// 则回退取 [fallbackCol] 作为备注，解决「备注填在备注列右边一格」
/// 导致备注整列丢失的问题（如铲车绩效表把「加/叉车」写在备注列右侧）。
/// [fallbackCol] 仅接受非纯数字的文本，避免把错位空列里的杂散数字当备注。
String? _readRemark(List<dynamic> row, int? remarkCol, int? fallbackCol) {
  String? pick(int? c) {
    if (c == null || c >= row.length) return null;
    final t = _text(row[c]) ?? '';
    return t.isEmpty ? null : t;
  }
  final primary = pick(remarkCol);
  if (primary != null) return _cleanRemark(primary);
  final fb = pick(fallbackCol);
  if (fb != null && !_isPureNumber(fb)) return _cleanRemark(fb);
  return null;
}

/// 读取某行「加班」列的值；非空（且非纯 0）表示本行（司机当天该班次）为加班班次。
/// 用于把加班信息并入住注，与 OCR 对账方案"备注含『加班』即判加班"的约定一致。
/// 注：普通行的加班列常为「0」或留空，纯 0 视为无加班，避免误标。
String? _readOvertime(List<dynamic> row, int? overtimeCol) {
  if (overtimeCol == null || overtimeCol >= row.length) return null;
  final t = _text(row[overtimeCol]) ?? '';
  final trimmed = t.trim();
  if (trimmed.isEmpty) return null;
  // 纯数字 0（如「0」「0.0」）视为无加班，避免普通行被误标为加班班次
  if (RegExp(r'^-?0(\.0+)?$').hasMatch(trimmed)) return null;
  return t;
}

/// 把加班信息并入备注：加班列有值 → 末尾补『加班』关键字（供 OCR 对账判加班）。
/// 与手动录入"备注写加班"的约定一致；备注原样内容保留，仅追加关键字。
String? _mergeOvertimeRemark(String? remark, String? overtimeValue) {
  if (overtimeValue == null || overtimeValue.isEmpty) return remark;
  final base = (remark != null && remark.isNotEmpty) ? remark : null;
  return [if (base != null) base, '加班'].join('·');
}

/// 判断字符串是否为纯数字（整数或小数），用于备注兜底列过滤杂散数字。
bool _isPureNumber(String s) => RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s.trim());

/// 清洗列名：剥离结尾的「(分隔符) 数字 元?」，提取单价。
/// 兼容多种写法：
/// 「外倒装车1.8元」→ 外倒装车 + 1.8；
/// 「倒货/1.8」→ 倒货 + 1.8（无「元」也识别）；
/// 「内倒装车，端货1.8元」→ 内倒装车/端货 + 1.8；
/// 「货场归剁」→ 货场归剁 + null。
CleanedColumn _cleanColumn(String raw) {
  final m =
      RegExp(r'^(.*?)(?:[，,\s/]\s*)?(\d+(?:\.\d+)?)\s*元?\s*$').firstMatch(raw);
  if (m != null) {
    final price = double.parse(m.group(2)!);
    return CleanedColumn(
      _canonicalJobType(m.group(1)!.trim().replaceAll('，', '/'),
          price: price),
      price,
    );
  }
  return CleanedColumn(_canonicalJobType(raw.trim()), null);
}

/// 把一行表头解析为 [_HeaderInfo]（姓名/车号/备注/船名/日期/班次/加班 + 作业列）。
/// 逻辑与 parseXlsx 中内联的列识别一致，便于行循环内「遇到新子表头重新解析」。
_HeaderInfo _analyzeHeader(List<dynamic> headerCells) {
  int? nameCol, vehCol, remarkCol, boatCol, dateCol, shiftCol, overtimeCol, yardCol;
  final jobCols = <int, CleanedColumn>{};
  final rawJobCols = <int, String>{};
  for (int c = 0; c < headerCells.length; c++) {
    final h = _text(headerCells[c]) ?? '';
    if (h.isEmpty) continue;
    if (h == '姓名') {
      nameCol = c;
      continue;
    }
    if (h == '车号' || h.contains('车牌') || h.contains('车辆')) {
      vehCol = c;
      continue;
    }
    if (h.contains('备注') || h.contains('说明')) {
      remarkCol = c;
      continue;
    }
    // 船名列：挖掘机、56道卸船等场景按船统计作业量。用「含『船』或『驳』」
    // 宽泛匹配，兼容各队长五花八门的写法（船名/船号/船次/驳船/船驳…），
    // 同时不会误命中铲车表的『货场装车/火车装车』等列（货场类不含船/驳）。
    if (h.contains('船') || h.contains('驳')) {
      boatCol = c;
      continue;
    }
    // 货场（场地）列：表内显式「场地/区域」或独立「货场」列时，逐行取该列值作货场。
    // 注意只认独立列名，避免把「货场装车/货场归垛」等作业类型误判为货场列。
    if (h == '货场' || h.contains('场地') || h.contains('区域')) {
      final ycIdx = c;
      yardCol = ycIdx;
      continue;
    }
    if (h.contains('日期') || h.contains('时间')) {
      dateCol = c;
      continue;
    }
    if (h.contains('班次') || h.contains('白班') || h.contains('夜班') || h.contains('班别')) {
      shiftCol = c;
      continue;
    }
    // 加班列：含「加班」或精确「加」（避免误伤挖掘机「加高」作业类型），
    // 其值作为每条记录的备注，不计入车数。
    if (h.contains('加班') || h.trim() == '加' || h.contains('加时') || h.contains('加班费')) {
      overtimeCol = c;
      continue;
    }
    // 签字 / 签名 / 复核 / 确认 等列不参与任何识别
    if (h.contains('签字') || h.contains('签名') || h.contains('复核') || h.contains('确认')) {
      continue;
    }
    // 米 / 吨 / 方 等非「车次」单位列不计入车数；
    // 但挖掘机「封垛（米）」是作业类型，米数即车数（按车算钱），须放行、计入车数。
    if ((h.contains('米') || h.contains('吨') || h.contains('方')) &&
        !h.contains('封垛') &&
        !h.contains('封跺')) {
      continue;
    }
    // 准驾车型 / 有效期 / 驾照 等花名册字段不是作业类型，避免误当归数
    if (h.contains('准驾') || h.contains('车型') || h.contains('有效期') || h.contains('驾照')) {
      continue;
    }
    jobCols[c] = _cleanColumn(h);
    rawJobCols[c] = h;
  }

  // 备注兜底列：若表头「备注」列右侧紧跟一个无表头的空列，
  // 说明该列常被当作备注的实际填写位置（备注列错位一格）。
  // 行解析时优先取对齐的备注列，取空则回退到此列（见 _readRemark）。
  int? remarkFallbackCol;
  if (remarkCol != null && remarkCol + 1 < headerCells.length) {
    final rightHeader = _text(headerCells[remarkCol + 1]) ?? '';
    if (rightHeader.isEmpty) remarkFallbackCol = remarkCol + 1;
  }

  return _HeaderInfo(
    nameCol: nameCol,
    vehCol: vehCol,
    remarkCol: remarkCol,
    remarkFallbackCol: remarkFallbackCol,
    boatCol: boatCol,
    dateCol: dateCol,
    shiftCol: shiftCol,
    overtimeCol: overtimeCol,
    yardCol: yardCol,
    jobCols: jobCols,
    rawJobCols: rawJobCols,
  );
}

/// 识别整表（首个区域）的货场：先看 sheet 名，再看表头上方标题行。
/// 取不到返回 null，交 UI 手动兜底。
String? _detectSheetYard(String sheetName, List<List<dynamic>> rows, int headerIdx) {
  final fromName = Yards.canonicalYard(sheetName);
  if (fromName != null) return fromName;
  for (int r = 0; r < headerIdx; r++) {
    for (final c in rows[r]) {
      final t = _text(c);
      if (t != null && t.isNotEmpty) {
        final y = Yards.canonicalYard(t);
        if (y != null) return y;
      }
    }
  }
  return null;
}

/// 识别新子表头所属区域的货场：向上扫描 1~3 行，命中含货场关键字的标题单元格
/// （如「56道货场绩效表」）即返回。取不到返回 null（沿用当前区域货场）。
String? _detectRegionYard(List<List<dynamic>> rows, int headerRow) {
  for (int k = 1; k <= 3; k++) {
    final rr = headerRow - k;
    if (rr < 0) break;
    for (final c in rows[rr]) {
      final t = _text(c);
      if (t != null && t.isNotEmpty) {
        final y = Yards.canonicalYard(t);
        if (y != null) return y;
      }
    }
  }
  return null;
}

/// 判断 [cand] 是否为与 [cur] 结构不同的「新子表头」（而非分页重复表头）。
/// 以作业类型归一名集合是否相同区分：集合相同视为同源分页表头，
/// 集合不同（含列数不同）视为新子表，需切换列映射。
/// 但若两张子表「作业类型列集合相同、而货场列/船名列不同」，说明列映射其实不一致，
/// 应判为新子表并切换列映射，否则货场归属会错乱。故仅当作业类型列、货场列、
/// 船名列都一致时才视为同源分页表头。
bool _isDifferentHeader(_HeaderInfo cand, _HeaderInfo cur) {
  if (cand.jobNames.length != cur.jobNames.length) return true;
  for (final n in cand.jobNames) {
    if (!cur.jobNames.contains(n)) return true;
  }
  // 作业类型列集合相同，再比较货场列/船名列是否一致
  if (cand.yardCol != cur.yardCol) return true;
  if (cand.boatCol != cur.boatCol) return true;
  return false;
}

/// 合并两组作业类型合计（同名累加），用于把同一 sheet 内多张子表的合计行
/// 累加为整体对账基准（如南货场合计 + 56道合计）。
Map<String, int> _mergeTotals(Map<String, int>? a, Map<String, int> b) {
  final m = Map<String, int>.from(a ?? {});
  b.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
  return m;
}

// ═══════════════════════════════════════════════════════════════════
// 内部数据结构 + Fallback 解析器
// ═══════════════════════════════════════════════════════════════════

/// 抽象工作表，屏蔽 [SpreadsheetDecoder] 与 fallback 解析器的差异。
class _RawTable {
  final String name;
  final List<List<dynamic>> rows;
  _RawTable(this.name, this.rows);
}

/// 抽象工作簿。
class _RawWorkbook {
  final Map<String, _RawTable> tables;
  _RawWorkbook(this.tables);
}

/// 将 [SpreadsheetDecoder] 的结果转为 [_RawWorkbook]。
_RawWorkbook _fromSpreadsheetDecoder(SpreadsheetDecoder decoder) {
  final tables = <String, _RawTable>{};
  for (final entry in decoder.tables.entries) {
    tables[entry.key] = _RawTable(entry.key, entry.value.rows);
  }
  return _RawWorkbook(tables);
}

/// 解析旧版 Excel 97-2003 (.xls) 文件（BIFF8），转为 [_RawWorkbook]。
_RawWorkbook _fromExcel2003(Uint8List bytes) {
  final reader = XlsReader.fromBytes(bytes);
  reader.open();

  final tables = <String, _RawTable>{};
  for (int i = 0; i < reader.sheetCount; i++) {
    final sheet = reader.sheet(i);
    final rows = <List<dynamic>>[];
    if (sheet.lastRow > sheet.firstRow && sheet.lastCol > sheet.firstCol) {
      for (int r = sheet.firstRow; r < sheet.lastRow; r++) {
        final row = <dynamic>[];
        for (int c = sheet.firstCol; c < sheet.lastCol; c++) {
          final v = sheet.cell(r, c);
          // 将 null 统一成空字符串，与 xlsx 解析器行为一致
          row.add(v ?? '');
        }
        rows.add(row);
      }
    }
    tables[reader.sheetNames[i]] = _RawTable(reader.sheetNames[i], rows);
  }
  return _RawWorkbook(tables);
}

/// Fallback 解析器：当 spreadsheet_decoder 因不支持批注/复杂格式而抛
/// UnsupportedError 时，用纯 Dart ZIP+XML 解析 xlsx。
///
/// 只实现导入需要的最小功能集（读取单元格文本/数字/日期），
/// 不支持样式/公式/合并单元格等高级特性——对司机绩效表足够了。
_RawWorkbook _fallbackDecodeBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  // M5 防护：压缩炸弹检测。恶意 xlsx 可极小体积解压出海量/超大文件，
  // 直接 OOM 或长时间占用。解压后立即校验条目数与单文件大小上限。
  const maxFiles = 2000;
  const maxFileSize = 50 * 1024 * 1024; // 50MB
  if (archive.files.length > maxFiles) {
    throw Exception('xlsx 内文件数过多（疑似压缩炸弹），已拒绝解析');
  }
  for (final f in archive.files) {
    if (f.size > maxFileSize) {
      throw Exception('xlsx 内存在超大文件（疑似压缩炸弹），已拒绝解析');
    }
  }

  // 提取所有文件内容
  final files = <String, String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    // 跳过二进制媒体文件（图片等），只读 XML 文本
    if (file.name.endsWith('.xml') ||
        file.name.endsWith('.rels') ||
        file.name == '[Content_Types].xml') {
      try {
        files[file.name] =
            String.fromCharCodes(file.content as List<int>);
      } catch (_) {
        // 二进制内容跳过
      }
    }
  }

  // 1) 解析 workbook.xml → sheet 名称列表 + rId 映射
  final sheetIdToRid = <int, String>{};
  final ridToTarget = <String, String>{};
  final wbXml = files['xl/workbook.xml'] ?? '';
  // <sheet name="xxx" sheetId="1" r:id="rId2"/> （注意 XML 用小写 r:id）
  for (final m in RegExp(r'<sheet\s+name="([^"]*)"\s+sheetId="(\d+)".*?r:id="([^"]*)"')
      .allMatches(wbXml)) {
    final sid = int.tryParse(m.group(2)!) ?? 0;
    sheetIdToRid[sid] = m.group(3)!;
  }

  // 2) 解析 workbook.xml.rels → rId → Target 映射
  final relsXml = files['xl/_rels/workbook.xml.rels'] ?? '';
  for (final m in RegExp(r'Id="([^"]*)"[^>]*Target="([^"]*)"').allMatches(relsXml)) {
    ridToTarget[m.group(1)!] = m.group(2)!;
  }

  // 3) 解析共享字符串表
  final sharedStrings = <String>[];
  final sstXml = files['xl/sharedStrings.xml'] ?? '';
  if (sstXml.isNotEmpty) {
    // <si><t>文本</t></si> 或 <si><t xml:space="preserve">文本</t></si>
    // 富文本：<si><r><t>a</t></r><r><t>b</t></r></si> 需把多段 <t> 拼接合并。
    for (final m in RegExp(r'<si[^>]*>(.*?)</si>', dotAll: true)
        .allMatches(sstXml)) {
      final siContent = m.group(1) ?? '';
      final sb = StringBuffer();
      for (final t in RegExp(r'<t(?:\s+[^>]*)?>([^<]*)</t>', dotAll: true)
          .allMatches(siContent)) {
        sb.write(t.group(1) ?? '');
      }
      // 解码 XML 实体转义（&lt; &gt; &quot; &apos; &amp;，注意 &amp; 最后替换）
      sharedStrings.add(_unescapeXml(sb.toString()).trim());
    }
  }

  // 4) 解析每个 worksheet
  final tables = <String, _RawTable>{};
  // 按 sheetId 排序保证顺序一致
  final sortedIds = sheetIdToRid.keys.toList()..sort();
  for (final sid in sortedIds) {
    final rid = sheetIdToRid[sid];
    if (rid == null) continue;
    final target = ridToTarget[rid];
    if (target == null) continue;

    // 从 rels Target 中提取 sheet 名称（如 "worksheets/sheet1.xml"）
    // 名称来自 workbook.xml 中的 name 属性
    final nameMatch =
        RegExp('sheetId="$sid"[^>]*name="([^"]*)"').firstMatch(wbXml);
    final sheetName = nameMatch?.group(1) ?? 'Sheet$sid';

    final sheetPath = 'xl/$target';
    final sheetXml = files[sheetPath];
    if (sheetXml == null) continue;

    final rows = _parseSheetXml(sheetXml, sharedStrings);
    tables[sheetName] = _RawTable(sheetName, rows);
  }

  if (tables.isEmpty) {
    throw Exception(
        'Fallback 解析失败：未找到任何工作表数据。'
        '该文件可能不是有效的 xlsx 格式，或已严重损坏。');
  }

  return _RawWorkbook(tables);
}

/// 解析单个 worksheet XML → 二维单元格数据。
List<List<dynamic>> _parseSheetXml(String xml, List<String> sharedStrings) {
  final rows = <List<dynamic>>[];

  // 定位 <sheetData> 块
  final dataStart = xml.indexOf('<sheetData>');
  if (dataStart < 0) return rows;
  final dataEnd = xml.indexOf('</sheetData>', dataStart);
  final dataXml =
      dataEnd > dataStart ? xml.substring(dataStart, dataEnd + 12) : '';

  // 解析每一行 <row r="N">...</row>
  for (final rowMatch in RegExp(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>',
          dotAll: true)
      .allMatches(dataXml)) {
    final rowContent = rowMatch.group(2) ?? '';

    // 解析该行内所有单元格 <c r="A1" t="s|inlineStr"><v>值</v></c>
    final cells = <dynamic>[];

    // 先收集有明确列号的单元格。
    // 兼容富文本：内联字符串 <is><r><t>…</t></r>…</is> 需拼接多段 <t>，
    // 且 <v>/<t> 文本可能含 XML 实体转义（&amp; 等），需解码。
    final colValues = <int, dynamic>{};
    for (final cMatch in RegExp(
            r'<c\s+r="([A-Z]+)(\d+)"(?:\s+t="([^"]*)")?[^>]*>(.*?)</c>',
            dotAll: true)
        .allMatches(rowContent)) {
      final colRef = cMatch.group(1)!; // 如 "A", "B", "AA"
      final type = cMatch.group(3);     // "s"=共享字符串, "inlineStr", "str", null=数字
      final inner = cMatch.group(4) ?? ''; // <c> 内部 XML

      final colIdx = _colRefToIndex(colRef);

      dynamic value;
      if (type == 's') {
        // 共享字符串索引：<v>idx</v>
        final vText = RegExp(r'<v>([^<]*)</v>').firstMatch(inner)?.group(1);
        final idx = vText != null ? int.tryParse(vText) : null;
        value = (idx != null && idx < sharedStrings.length)
            ? sharedStrings[idx]
            : (vText != null && vText.isNotEmpty ? vText : '');
      } else if (type == 'inlineStr') {
        // 内联字符串：可能含富文本 runs，拼接所有 <t> 段并解码实体
        final sb = StringBuffer();
        for (final t in RegExp(r'<t(?:\s+[^>]*)?>([^<]*)</t>', dotAll: true)
            .allMatches(inner)) {
          sb.write(t.group(1) ?? '');
        }
        final raw = sb.toString();
        value = raw.isNotEmpty ? _unescapeXml(raw) : '';
      } else if (type == 'str') {
        // 公式字符串结果：<v>文本</v>
        final vText = RegExp(r'<v>([^<]*)</v>').firstMatch(inner)?.group(1);
        value = vText != null && vText.isNotEmpty ? _unescapeXml(vText) : '';
      } else {
        // 数字（或空单元格）：<v>数字</v>
        final vText = RegExp(r'<v>([^<]*)</v>').firstMatch(inner)?.group(1);
        if (vText != null && vText.isNotEmpty) {
          final d = double.tryParse(vText);
          if (d != null) {
            // 整数返回 int，小数返回 double
            value = d == d.roundToDouble() ? d.toInt() : d;
          } else {
            value = vText;
          }
        } else {
          value = '';
        }
      }
      colValues[colIdx] = value;
    }

    // 构建完整行（稀疏→密集）
    if (colValues.isNotEmpty) {
      final maxCol = colValues.keys.reduce((a, b) => a > b ? a : b);
      for (int i = 0; i <= maxCol; i++) {
        cells.add(colValues[i] ?? '');
      }
      rows.add(cells);
    }
  }

  return rows;
}

/// 解码 XML 实体转义为普通字符。
/// 仅处理这 5 个最常见的实体；注意替换顺序——&amp; 必须最后替换，
/// 否则会先把已解码出的 &lt; 等里的 & 再拼成 &amp;lt; 造成二次错误。
String _unescapeXml(String s) {
  return s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 列引用转 0-based 索引：A=0, B=1, ..., Z=25, AA=26, ...
int _colRefToIndex(String ref) {
  int idx = 0;
  for (var i = 0; i < ref.length; i++) {
    idx = idx * 26 + (ref.codeUnitAt(i) - 64); // 'A'=65
  }
  return idx - 1;
}

// ═══════════════════════════════════════════════════════════════════
// Raw 版本的辅助方法（与原版逻辑相同，但操作 [_RawWorkbook]）
// ═══════════════════════════════════════════════════════════════════

Map<String, bool> _scanImportableRaw(_RawWorkbook wb) {
  final map = <String, bool>{};
  for (final entry in wb.tables.entries) {
    map[entry.key] = _sheetImportableRaw(entry.value, entry.key);
  }
  return map;
}

bool _sheetImportableRaw(_RawTable table, String name) {
  int? headerIdx;
  for (int r = 0; r < table.rows.length; r++) {
    if (table.rows[r].any((c) => (_text(c) ?? '').contains('姓名'))) {
      headerIdx = r;
      break;
    }
  }
  if (headerIdx == null) return false;
  final header = table.rows[headerIdx];
  if (_isNonPerfSheet(name, header)) return false;
  for (int r = headerIdx + 1; r < table.rows.length; r++) {
    for (final c in table.rows[r]) {
      final v = _raw(c);
      if (v is num && v != 0) return true;
    }
  }
  return false;
}

String? _pickDefaultSheetRaw(_RawWorkbook wb) {
  const preferred = ['绩效', '铲车', '装载机', '挖掘机'];
  for (final k in preferred) {
    for (final name in wb.tables.keys) {
      if (name.contains(k) &&
          _sheetImportableRaw(wb.tables[name]!, name)) {
        return name;
      }
    }
  }
  for (final name in wb.tables.keys) {
    if (_sheetImportableRaw(wb.tables[name]!, name)) return name;
  }
  return null;
}

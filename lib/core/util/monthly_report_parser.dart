import 'dart:math';

import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/monthly_report.dart';

/// 月度作业量汇总表 OCR 解析器。
///
/// 输入：OCR 识别出的文本行（已做数字纠错）。
/// 输出：结构化 [MonthlyReport]。
///
/// 支持的表格式样（见用户样张）：
///   姓名 | 1 早 晚 | 2 早 晚 | ... | 31 早 晚 | 合计
///   刘松祥
///   1.2元/车  数值 数值 ... 数值
///   1.8元/车  数值 数值 ... 数值
///   5元/车    数值 数值 ... 数值
///   王海平
///   ...
class MonthlyReportParser {
  /// 姓名列最右侧边界：x < 此值视为姓名列内容。
  static const double _nameColumnRight = 90;

  /// 单个数字 token 的最小宽度阈值，小于此值可能是噪声。
  static const double _minTokenWidth = 8;

  /// 解析月报。
  ///
  /// [lines] 为 OCR 输出；[year]/[month] 可选，默认当前年月。
  static MonthlyReport parse(
    List<OcrLine> lines, {
    int? year,
    int? month,
  }) {
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;

    // 1. 按行从上到下排序，方便按人名块读取。
    final sorted = lines.where((l) => l.text.trim().isNotEmpty).toList()
      ..sort((a, b) {
        final ta = a.boundingBox?.top ?? 0;
        final tb = b.boundingBox?.top ?? 0;
        if ((ta - tb).abs() > 8) return ta.compareTo(tb);
        // 同行内按从左到右。
        return (a.boundingBox?.left ?? 0).compareTo(b.boundingBox?.left ?? 0);
      });

    // 2. 全局扫描建立「日期+班次」列映射（OCR 常把表头拆成多行，
    //    不能假设姓名/合计/早/晚在同一条 OCR 行里）。
    final columns = _buildColumns(sorted);

    // 3. 逐行扫描，聚合成「人名块」。
    final entries = <ReportEntry>[];
    final rows = _groupIntoRows(sorted);

    String? currentName;
    final pendingPriceRows = <_PriceRow>[];

    for (final row in rows) {
      final leftMost = _leftMostLine(row);
      final leftX = leftMost.boundingBox?.left ?? 0;

      // 人名行：靠左、2-4 个纯中文字符、不含数字。
      if (leftX < _nameColumnRight && _looksLikeName(row)) {
        // 把上一个人的 pendingPriceRows  flush。
        if (currentName != null && pendingPriceRows.isNotEmpty) {
          entries.addAll(
            _buildEntriesForPerson(currentName, pendingPriceRows, columns, y, m),
          );
          pendingPriceRows.clear();
        }
        currentName = row.map((l) => l.text.trim()).join('').replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
        continue;
      }

      // 单价行：包含 "元/车"。
      final price = _extractPrice(row);
      if (price != null && currentName != null) {
        pendingPriceRows.add(_PriceRow(price: price, tokens: _extractNumberTokens(row, columns)));
        continue;
      }

      // 数据行：以数字为主，且前面有人名和单价行时，归入最近一个单价行。
      if (currentName != null && pendingPriceRows.isNotEmpty && _looksLikeNumberRow(row)) {
        pendingPriceRows.last.tokens.addAll(_extractNumberTokens(row, columns));
      }
    }

    // flush 最后一个人。
    if (currentName != null && pendingPriceRows.isNotEmpty) {
      entries.addAll(
        _buildEntriesForPerson(currentName, pendingPriceRows, columns, y, m),
      );
    }

    return MonthlyReport(year: y, month: m, entries: entries);
  }

  // ------------------------------------------------------------------
  // 表头 / 列定位（全局扫描，不依赖表头单行）
  // ------------------------------------------------------------------

  /// 提取所有整数 token（值 1-9999），保留几何信息供列对齐。
  static List<_Token> _collectNumberTokens(List<OcrLine> lines) {
    final tokens = <_Token>[];
    for (final line in lines) {
      final text = line.text;
      for (final m in RegExp(r'\d+').allMatches(text)) {
        final n = int.tryParse(m.group(0)!);
        if (n == null || n < 0 || n > 9999) continue;
        final left = (line.boundingBox?.left ?? 0) + _charOffset(line, m.start);
        final width = _approxTokenWidth(line, m.start, m.end);
        if (width < _minTokenWidth) continue;
        tokens.add(_Token(value: n, left: left, width: width, line: line));
      }
    }
    return tokens;
  }

  /// 全局扫描建立「日期+班次」列映射。
  ///
  /// 优先用「早/晚」标记按 x 坐标配对定位每日起/晚区间；
  /// 退回到「日期数字等距」；最后兜底 K-means 聚类。
  static List<_Column> _buildColumns(List<OcrLine> allLines) {
    final cols = <_Column>[];

    // 收集「早」「晚」标记的 x 坐标（表头里每个日期都有一对）。
    final earlyLefts = <double>[];
    final lateLefts = <double>[];
    for (final line in allLines) {
      final left = line.boundingBox?.left ?? 0;
      final t = line.text;
      if (t.contains('早')) earlyLefts.add(left + 1);
      if (t.contains('晚')) lateLefts.add(left + 1);
    }
    earlyLefts.sort();
    lateLefts.sort();

    if (earlyLefts.isNotEmpty && lateLefts.isNotEmpty) {
      // 对每个 早 标记找其右侧最近的 晚 标记，配成一对（一日起/晚区间）。
      int li = 0;
      for (int i = 0; i < earlyLefts.length && i < 31; i++) {
        final e = earlyLefts[i];
        double? l;
        while (li < lateLefts.length && lateLefts[li] <= e) {
          li++;
        }
        if (li >= lateLefts.length) break;
        l = lateLefts[li];
        li++;
        final nextEarly = (i + 1 < earlyLefts.length)
            ? earlyLefts[i + 1]
            : (l + (l - e)); // 用本区间宽度外推末列右界
        cols.add(_Column(day: i + 1, shift: '早', left: e, right: l));
        cols.add(_Column(day: i + 1, shift: '晚', left: l, right: nextEarly));
      }
      if (cols.isNotEmpty) return cols;
    }

    // 备用：用日期数字（1-31）的位置等距分列。
    final dateTokens =
        _collectNumberTokens(allLines).where((t) => t.value >= 1 && t.value <= 31).toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    if (dateTokens.length >= 2) {
      for (int i = 0; i < dateTokens.length && i < 31; i++) {
        final left = dateTokens[i].left;
        final right =
            (i + 1 < dateTokens.length) ? dateTokens[i + 1].left : left + 50;
        final mid = (left + right) / 2;
        cols.add(_Column(day: i + 1, shift: '早', left: left, right: mid));
        cols.add(_Column(day: i + 1, shift: '晚', left: mid, right: right));
      }
      return cols;
    }

    // 兜底：K-means 样式等距生成 62 列（31 天 × 2 班）。
    final tokens = _collectNumberTokens(allLines);
    if (tokens.isNotEmpty) {
      tokens.sort((a, b) => a.left.compareTo(b.left));
      const colWidth = 35.0;
      double cursor = tokens.first.left - colWidth / 2;
      int day = 1;
      while (cursor < tokens.last.right + colWidth && day <= 31) {
        final left = cursor;
        final right = cursor + colWidth;
        cols.add(_Column(day: day, shift: '早', left: left, right: left + colWidth / 2));
        cols.add(_Column(day: day, shift: '晚', left: left + colWidth / 2, right: right));
        cursor += colWidth;
        day++;
      }
    }

    return cols;
  }

  // ------------------------------------------------------------------
  // 行分组 / 人名识别 / 单价识别
  // ------------------------------------------------------------------

  /// 把 OCR 行按垂直位置合并成逻辑行（OCR 可能把一行拆成多个 block）。
  static List<List<OcrLine>> _groupIntoRows(List<OcrLine> lines) {
    final rows = <List<OcrLine>>[];
    for (final line in lines) {
      if (line.text.trim().isEmpty) continue;
      final top = line.boundingBox?.top ?? 0;
      bool placed = false;
      for (final row in rows) {
        final rowTop = row.first.boundingBox?.top ?? 0;
        if ((top - rowTop).abs() < 18) {
          row.add(line);
          // 保持行内从左到右。
          row.sort((a, b) => (a.boundingBox?.left ?? 0).compareTo(b.boundingBox?.left ?? 0));
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([line]);
    }
    // 对行从上到下排序。
    rows.sort((a, b) => ((a.first.boundingBox?.top ?? 0) - (b.first.boundingBox?.top ?? 0)).toInt());
    return rows;
  }

  static OcrLine _leftMostLine(List<OcrLine> row) => row.reduce((a, b) =>
      ((a.boundingBox?.left ?? double.infinity) < (b.boundingBox?.left ?? double.infinity)) ? a : b);

  static bool _looksLikeName(List<OcrLine> row) {
    final text = row.map((l) => l.text.trim()).join('');
    if (text.length < 2 || text.length > 5) return false;
    // 去除常见非姓名字符后应全为中文。
    final cleaned = text.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
    return cleaned.length >= 2 && cleaned.length <= 4 && !RegExp(r'[0-9元/车合计名]').hasMatch(text);
  }

  static double? _extractPrice(List<OcrLine> row) {
    final text = row.map((l) => l.text).join(' ');
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*元\s*/\s*车').firstMatch(text);
    if (m != null) return double.parse(m.group(1)!);
    return null;
  }

  static bool _looksLikeNumberRow(List<OcrLine> row) {
    final text = row.map((l) => l.text).join(' ');
    // 数字字符占比高，且不含 "元/车"。
    if (text.contains('元/车')) return false;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
    final total = text.replaceAll(RegExp(r'\s'), '').length;
    return total > 0 && digits / total > 0.5;
  }

  // ------------------------------------------------------------------
  // 数值提取
  // ------------------------------------------------------------------

  static List<_Token> _extractNumberTokens(List<OcrLine> row, List<_Column> columns) {
    final tokens = <_Token>[];
    for (final line in row) {
      for (final m in RegExp(r'\d+').allMatches(line.text)) {
        final n = int.tryParse(m.group(0)!);
        if (n == null || n > 9999) continue;
        final left = (line.boundingBox?.left ?? 0) + _charOffset(line, m.start);
        final width = _approxTokenWidth(line, m.start, m.end);
        if (width < _minTokenWidth) continue;
        tokens.add(_Token(value: n, left: left, width: width, line: line));
      }
    }
    return tokens;
  }

  static List<ReportEntry> _buildEntriesForPerson(
    String name,
    List<_PriceRow> priceRows,
    List<_Column> columns,
    int year,
    int month,
  ) {
    final entries = <ReportEntry>[];
    final daysInMonth = DateTime(year, month + 1, 1).difference(DateTime(year, month, 1)).inDays;

    for (final pr in priceRows) {
      final cells = <ReportCell>[];
      int sum = 0;
      for (final col in columns) {
        if (col.day < 1 || col.day > daysInMonth) continue;
        // 找落在该列区间内的数字 token，取最近一个。
        final hits = pr.tokens.where((t) => t.center >= col.left && t.center <= col.right).toList();
        int count = 0;
        if (hits.isNotEmpty) {
          // 若列内多个 token，取和（偶有 OCR 把多位数拆成两个数）。
          count = hits.map((t) => t.value).fold(0, (a, b) => a + b);
        }
        cells.add(ReportCell(day: col.day, shift: col.shift, count: count));
        sum += count;
      }
      entries.add(ReportEntry(
        workerName: name,
        price: pr.price,
        cells: cells,
        total: sum,
      ));
    }
    return entries;
  }

  // ------------------------------------------------------------------
  // 辅助
  // ------------------------------------------------------------------

  static double _charOffset(OcrLine line, int charIndex) {
    final box = line.boundingBox;
    if (box == null || line.text.isEmpty) return 0;
    final ratio = charIndex / max(1, line.text.length);
    return (box.width * ratio);
  }

  static double _approxTokenWidth(OcrLine line, int start, int end) {
    final box = line.boundingBox;
    if (box == null || line.text.isEmpty) return 20;
    return box.width * (end - start) / max(1, line.text.length);
  }
}

class _Column {
  final int day;
  final String shift;
  final double left;
  final double right;

  _Column({required this.day, required this.shift, required this.left, required this.right});
}

class _Token {
  final int value;
  final double left;
  final double width;
  final OcrLine line;

  _Token({required this.value, required this.left, required this.width, required this.line});

  double get right => left + width;
  double get center => left + width / 2;
}

class _PriceRow {
  final double price;
  final List<_Token> tokens;

  _PriceRow({required this.price, required this.tokens});
}

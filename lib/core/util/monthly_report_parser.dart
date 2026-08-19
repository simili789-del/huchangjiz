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
  /// 单个数字 token 的最小宽度阈值，小于此值可能是噪声。
  static const double _minTokenWidth = 8;

  /// 解析月报。
  ///
  /// [lines] 为 OCR 输出；[year]/[month] 可选，默认当前年月。
  static MonthlyReport parse(
    List<OcrLine> lines, {
    int? year,
    int? month,
    int? imageWidth,
  }) {
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;
    final daysInMonth = DateTime(y, m + 1, 1).difference(DateTime(y, m, 1)).inDays;

    // 1. 按行从上到下排序，方便按人名块读取。
    final sorted = lines.where((l) => l.text.trim().isNotEmpty).toList()
      ..sort((a, b) {
        final ta = a.boundingBox?.top ?? 0;
        final tb = b.boundingBox?.top ?? 0;
        if ((ta - tb).abs() > 8) return ta.compareTo(tb);
        // 同行内按从左到右。
        return (a.boundingBox?.left ?? 0).compareTo(b.boundingBox?.left ?? 0);
      });

    // 2. 由表头「早/晚」标记（及日期数字兜底）外推 31 天均匀网格。
    final grid = _buildGrid(sorted, daysInMonth);

    // 3. 逐行扫描，聚合成「人名块」。
    final entries = <ReportEntry>[];
    final rows = _groupIntoRows(sorted);

    String? currentName;
    final pendingPriceRows = <_PriceRow>[];

    for (final row in rows) {
      final leftMost = _leftMostLine(row);
      final leftX = leftMost.boundingBox?.left ?? 0;

      // 人名行：靠左、2-4 个纯中文字符、不含数字。
      if (leftX < nameColumnRight(imageWidth) && _looksLikeName(row)) {
        if (currentName != null && pendingPriceRows.isNotEmpty) {
          entries.addAll(_buildEntriesForPerson(
              currentName, pendingPriceRows, grid, daysInMonth));
          pendingPriceRows.clear();
        }
        currentName =
            row.map((l) => l.text.trim()).join('').replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
        continue;
      }

      // 单价行：包含 "元/车"。
      final price = _extractPrice(row);
      if (price != null && currentName != null) {
        pendingPriceRows.add(_PriceRow(price: price, tokens: _extractNumberTokens(row)));
        continue;
      }

      // 数据行：以数字为主，且前面有人名和单价行时，归入最近一个单价行。
      if (currentName != null && pendingPriceRows.isNotEmpty && _looksLikeNumberRow(row)) {
        pendingPriceRows.last.tokens.addAll(_extractNumberTokens(row));
      }
    }

    // flush 最后一个人。
    if (currentName != null && pendingPriceRows.isNotEmpty) {
      entries.addAll(_buildEntriesForPerson(currentName, pendingPriceRows, grid, daysInMonth));
    }

    return MonthlyReport(year: y, month: m, entries: entries);
  }

  // ------------------------------------------------------------------
  // 表头 / 列网格（外推 31 天均匀网格，抗标记漏识别 + 抗倾斜）
  // ------------------------------------------------------------------

  /// 31 天均匀网格：每天占 [dayStep] 宽，前半 [halfDay] 为早班、后半为晚班。
  /// [originX] 为第 1 天早班列的左边；[dateRegionRight] 右侧为合计/备注，需排除。
  static _Grid _buildGrid(List<OcrLine> allLines, int daysInMonth) {
    final earlyXs = <double>[];
    final lateXs = <double>[];
    double? totalX;
    for (final line in allLines) {
      final left = line.boundingBox?.left ?? 0;
      final t = line.text;
      if (t.contains('早')) earlyXs.add(left);
      if (t.contains('晚')) lateXs.add(left);
      if (t.contains('合计')) totalX = totalX == null ? left : min(totalX, left);
    }
    earlyXs.sort();
    lateXs.sort();

    // 日期数字（1-31）作为兜底锚点。
    final dateTokens = _collectNumberTokens(allLines)
        .where((t) => t.value >= 1 && t.value <= 31)
        .map((t) => t.center)
        .toList()
      ..sort();

    double originX;
    double dayStep;

    if (earlyXs.length >= 2) {
      originX = earlyXs.first;
      dayStep = _medianGap(earlyXs);
    } else if (earlyXs.isNotEmpty && lateXs.isNotEmpty) {
      originX = earlyXs.first;
      dayStep = (lateXs.first - earlyXs.first).abs() * 2;
    } else if (lateXs.length >= 2) {
      dayStep = _medianGap(lateXs) * 2;
      originX = lateXs.first - dayStep / 2;
    } else if (dateTokens.length >= 2) {
      originX = dateTokens.first - _medianGap(dateTokens) / 2;
      dayStep = _medianGap(dateTokens);
    } else {
      // 全兜底：用全体数字 token 的最小 x 估算。
      final allC = _collectNumberTokens(allLines).map((t) => t.center).toList()..sort();
      originX = allC.isEmpty ? 0 : allC.first - 20;
      dayStep = allC.length >= 2
          ? (allC.last - allC.first) / max(1, daysInMonth)
          : 40;
    }

    if (dayStep <= 0) dayStep = 40;

    final gridEnd = originX + daysInMonth * dayStep + dayStep;
    final dateRegionRight = totalX == null ? gridEnd : min(gridEnd, totalX);

    return _Grid(
      originX: originX,
      dayStep: dayStep,
      halfDay: dayStep / 2,
      dateRegionRight: dateRegionRight,
      daysInMonth: daysInMonth,
    );
  }

  /// 相邻元素间距的中位数（用于从标记推断列间距）。
  static double _medianGap(List<double> xs) {
    if (xs.length < 2) return 0;
    final gaps = <double>[];
    for (int i = 1; i < xs.length; i++) {
      gaps.add(xs[i] - xs[i - 1]);
    }
    gaps.sort();
    final n = gaps.length;
    return n.isOdd ? gaps[n ~/ 2] : (gaps[n ~/ 2 - 1] + gaps[n ~/ 2]) / 2;
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
          row.sort((a, b) => (a.boundingBox?.left ?? 0).compareTo(b.boundingBox?.left ?? 0));
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([line]);
    }
    rows.sort((a, b) =>
        ((a.first.boundingBox?.top ?? 0) - (b.first.boundingBox?.top ?? 0)).toInt());
    return rows;
  }

  static OcrLine _leftMostLine(List<OcrLine> row) => row.reduce((a, b) =>
      ((a.boundingBox?.left ?? double.infinity) < (b.boundingBox?.left ?? double.infinity))
          ? a
          : b);

  /// 公开：判断一行文本是否像中文姓名（notifier 做姓名词典校正时复用）。
  static bool looksLikeNameLine(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
    return cleaned.length >= 2 &&
        cleaned.length <= 4 &&
        !RegExp(r'[0-9元/车合计名]').hasMatch(text);
  }

  static bool _looksLikeName(List<OcrLine> row) =>
      looksLikeNameLine(row.map((l) => l.text.trim()).join(''));

  static double? _extractPrice(List<OcrLine> row) {
    final text = row.map((l) => l.text).join(' ');
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*元\s*/\s*车').firstMatch(text);
    if (m != null) return double.parse(m.group(1)!);
    return null;
  }

  static bool _looksLikeNumberRow(List<OcrLine> row) {
    final text = row.map((l) => l.text).join(' ');
    if (text.contains('元/车')) return false;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
    final total = text.replaceAll(RegExp(r'\s'), '').length;
    return total > 0 && digits / total > 0.5;
  }

  // ------------------------------------------------------------------
  // 数值提取
  // ------------------------------------------------------------------

  static List<_Token> _extractNumberTokens(List<OcrLine> row) {
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

  // ------------------------------------------------------------------
  // 按行对齐赋值（抗倾斜核心）
  // ------------------------------------------------------------------

  /// 把一行（可能跨多行物理行）的数字 token 归位到 (day, shift) 网格。
  ///
  /// 关键：OCR 照片一旦倾斜，每行数字的横坐标相对表头标记会整体偏移一个常数
  /// （同一行 y 相同，偏移量恒定），且列间距在旋转下近似等比缩放。因此逐行
  /// 计算「中值偏移 δ」把网格对齐到该行，再按区间归属到具体 (day, shift)，
  /// 从根本上消除「整列右移一位」的级联错位。
  static Map<int, int> _assignRow(List<_Token> tokens, _Grid g) {
    final result = <int, int>{};
    final valid = tokens
        .where((t) => t.center <= g.dateRegionRight && t.center >= g.originX - g.dayStep)
        .toList();
    if (valid.isEmpty) return result;

    // 中值偏移 δ：每个 token 到其所在（未偏移）网格格中心的距离的中值。
    final diffs = <double>[];
    for (final t in valid) {
      final rel = t.center - g.originX;
      final d0 = (rel / g.dayStep).floor();
      if (d0 < 0 || d0 >= g.daysInMonth) continue;
      final shift = (rel - d0 * g.dayStep) < g.halfDay ? '早' : '晚';
      diffs.add(t.center - _cellCenterX(g, d0, shift));
    }
    if (diffs.isEmpty) return result;
    final delta = _median(diffs);
    final origin = g.originX + delta;

    for (final t in valid) {
      final rel = t.center - origin;
      if (rel < 0) continue;
      final d0 = (rel / g.dayStep).floor();
      if (d0 < 0 || d0 >= g.daysInMonth) continue;
      final shift = (rel - d0 * g.dayStep) < g.halfDay ? '早' : '晚';
      final key = d0 * 2 + (shift == '早' ? 0 : 1);
      result[key] = (result[key] ?? 0) + t.value;
    }
    return result;
  }

  static double _cellCenterX(_Grid g, int d0, String shift) {
    final base = g.originX + d0 * g.dayStep;
    return shift == '早' ? base + g.halfDay / 2 : base + g.halfDay + g.halfDay / 2;
  }

  static double _median(List<double> xs) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  static List<ReportEntry> _buildEntriesForPerson(
    String name,
    List<_PriceRow> priceRows,
    _Grid grid,
    int daysInMonth,
  ) {
    final entries = <ReportEntry>[];
    for (final pr in priceRows) {
      // 按物理行（line.top）分组，逐行对齐后合并，兼容多行数字 + 倾斜。
      final byRow = <double, List<_Token>>{};
      for (final t in pr.tokens) {
        final top = t.line.boundingBox?.top ?? 0;
        final key = (top / 12).round() * 12.0;
        byRow.putIfAbsent(key, () => []).add(t);
      }

      final cellMap = <int, int>{};
      for (final rowTokens in byRow.values) {
        final counts = _assignRow(rowTokens, grid);
        counts.forEach((k, v) => cellMap[k] = (cellMap[k] ?? 0) + v);
      }

      final cells = <ReportCell>[];
      int sum = 0;
      for (int day = 1; day <= daysInMonth; day++) {
        for (final shift in const ['早', '晚']) {
          final k = (day - 1) * 2 + (shift == '早' ? 0 : 1);
          final c = cellMap[k] ?? 0;
          cells.add(ReportCell(day: day, shift: shift, count: c));
          sum += c;
        }
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

/// 姓名列最右侧边界默认值（无图片宽度时的兜底）。
const double _nameColumnRightFallback = 90;

/// 姓名列占图片宽度的比例上限。
const double _nameColumnRatio = 0.12;

/// 根据图片宽度计算姓名列右边界（相对化，适配不同分辨率）。
double nameColumnRight(int? imageWidth) {
  if (imageWidth == null || imageWidth <= 0) return _nameColumnRightFallback;
  return imageWidth * _nameColumnRatio;
}

class _Grid {
  final double originX;
  final double dayStep;
  final double halfDay;
  final double dateRegionRight;
  final int daysInMonth;

  _Grid({
    required this.originX,
    required this.dayStep,
    required this.halfDay,
    required this.dateRegionRight,
    required this.daysInMonth,
  });
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

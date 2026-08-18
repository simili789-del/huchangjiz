import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/core/util/monthly_report_parser.dart';
import 'package:yard_accounting/domain/entities/ocr_result.dart';

OcrLine _line(String text, double left, double top, {double width = 40}) =>
    OcrLine(text: text, boundingBox: Rect.fromLTRB(left, top, left + width, top + 18));

/// 生成一张「按真实比例」的整月月报布局（用于验证外推网格与抗倾斜）。
/// [data] 为 日期 -> {'早':车数, '晚':车数}。
/// [skew] 模拟照片旋转：仅数据行整体右移该像素量，表头/姓名不动。
List<OcrLine> _monthLines({
  required String name,
  required double price,
  required int daysInMonth,
  required double originX,
  required double dayStep,
  Map<int, Map<String, int>>? data,
  double top = 40,
  double skew = 0,
}) {
  final lines = <OcrLine>[];
  lines.add(_line('姓名', 10, 10, width: 30));
  for (int d = 1; d <= daysInMonth; d++) {
    final base = originX + (d - 1) * dayStep;
    lines.add(_line('$d', base + dayStep * 0.12, 10, width: dayStep * 0.3));
    lines.add(_line('早', base + dayStep * 0.05, 10, width: dayStep * 0.2));
    lines.add(_line('晚', base + dayStep * 0.55, 10, width: dayStep * 0.2));
  }
  lines.add(_line('合计', originX + daysInMonth * dayStep + dayStep * 0.5, 10, width: 40));
  lines.add(_line(name, 15, top, width: 40));
  lines.add(_line('${price}元/车', 20, top + 22, width: 70));
  for (int d = 1; d <= daysInMonth; d++) {
    final base = originX + (d - 1) * dayStep + skew;
    final early = data?[d]?['早'] ?? 0;
    final late = data?[d]?['晚'] ?? 0;
    if (early > 0) {
      lines.add(_line('$early', base + dayStep * 0.1, top + 44, width: dayStep * 0.25));
    }
    if (late > 0) {
      lines.add(_line('$late', base + dayStep * 0.6, top + 44, width: dayStep * 0.25));
    }
  }
  return lines;
}

void main() {
  group('MonthlyReportParser', () {
    test('能解析简化版月报表', () {
      final lines = <OcrLine>[
        // 表头
        _line('姓名', 10, 10, width: 30),
        _line('1', 120, 10, width: 20),
        _line('早', 110, 10, width: 16),
        _line('晚', 135, 10, width: 16),
        _line('2', 170, 10, width: 20),
        _line('早', 160, 10, width: 16),
        _line('晚', 185, 10, width: 16),
        _line('合计', 400, 10, width: 40),
        // 第一个人
        _line('张三', 15, 40, width: 40),
        _line('1.2元/车', 20, 62, width: 60),
        _line('5', 118, 62, width: 14),
        _line('3', 138, 62, width: 14),
        _line('2', 168, 62, width: 14),
        _line('0', 188, 62, width: 14),
        _line('1.8元/车', 20, 84, width: 60),
        _line('0', 118, 84, width: 14),
        _line('2', 138, 84, width: 14),
        _line('4', 168, 84, width: 14),
        _line('6', 188, 84, width: 14),
        // 第二个人
        _line('李四', 15, 120, width: 40),
        _line('5元/车', 25, 142, width: 50),
        _line('1', 118, 142, width: 14),
        _line('1', 138, 142, width: 14),
        _line('0', 168, 142, width: 14),
        _line('0', 188, 142, width: 14),
      ];

      final report = MonthlyReportParser.parse(lines, year: 2026, month: 8);

      expect(report.year, 2026);
      expect(report.month, 8);
      expect(report.entries.length, 3);

      final zhang12 = report.entries.firstWhere((e) => e.workerName == '张三' && e.price == 1.2);
      expect(zhang12.cells.length, 62); // 8 月 31 天 × 2 班
      expect(zhang12.cells.firstWhere((c) => c.day == 1 && c.shift == '早').count, 5);
      expect(zhang12.cells.firstWhere((c) => c.day == 1 && c.shift == '晚').count, 3);
      expect(zhang12.cells.firstWhere((c) => c.day == 2 && c.shift == '早').count, 2);
      expect(zhang12.cells.firstWhere((c) => c.day == 2 && c.shift == '晚').count, 0);
      expect(zhang12.total, 10);

      final zhang18 = report.entries.firstWhere((e) => e.workerName == '张三' && e.price == 1.8);
      expect(zhang18.total, 12);

      final li5 = report.entries.firstWhere((e) => e.workerName == '李四' && e.price == 5.0);
      expect(li5.total, 2);
    });

    test('姓名列可正确识别中文姓名', () {
      final lines = <OcrLine>[
        _line('姓名', 10, 10),
        _line('刘松祥', 12, 40),
        _line('1.2元/车', 20, 65),
        _line('0', 120, 65, width: 12),
      ];
      final report = MonthlyReportParser.parse(lines);
      expect(report.entries.length, 1);
      expect(report.entries.first.workerName, '刘松祥');
    });

    test('空单元格解析为 0', () {
      final lines = <OcrLine>[
        _line('姓名', 10, 10),
        _line('1', 120, 10),
        _line('早', 110, 10, width: 14),
        _line('晚', 135, 10, width: 14),
        _line('张三', 15, 40),
        _line('1.2元/车', 20, 62),
        _line('7', 118, 62, width: 14),
      ];
      final report = MonthlyReportParser.parse(lines);
      final entry = report.entries.first;
      expect(entry.cells.firstWhere((c) => c.shift == '早').count, 7);
      expect(entry.cells.firstWhere((c) => c.shift == '晚').count, 0);
    });

    test('31 天整月布局能正确归位到中间日期', () {
      final data = <int, Map<String, int>>{
        1: {'早': 5, '晚': 3},
        15: {'早': 7, '晚': 9},
        31: {'早': 2, '晚': 4},
      };
      final lines = _monthLines(
        name: '张三',
        price: 1.2,
        daysInMonth: 31,
        originX: 100,
        dayStep: 40,
        data: data,
      );
      final report = MonthlyReportParser.parse(lines, year: 2026, month: 8);
      final e = report.entries.firstWhere((x) => x.workerName == '张三' && x.price == 1.2);
      expect(e.cells.length, 62); // 31 天 × 2 班
      expect(e.cells.firstWhere((c) => c.day == 1 && c.shift == '早').count, 5);
      expect(e.cells.firstWhere((c) => c.day == 1 && c.shift == '晚').count, 3);
      // 中间日期（远离表头锚点）也能正确归位，证明 31 天网格外推有效。
      expect(e.cells.firstWhere((c) => c.day == 15 && c.shift == '早').count, 7);
      expect(e.cells.firstWhere((c) => c.day == 15 && c.shift == '晚').count, 9);
      expect(e.cells.firstWhere((c) => c.day == 31 && c.shift == '早').count, 2);
      expect(e.cells.firstWhere((c) => c.day == 31 && c.shift == '晚').count, 4);
      // 未填日期应为 0。
      expect(e.cells.firstWhere((c) => c.day == 10 && c.shift == '早').count, 0);
    });

    test('纠斜后的小残差（数据行整体右移 12px）仍能正确归位', () {
      // 大角度旋转（行偏移可达上百像素，远超半列宽）由「纠斜预处理」消除；
      // 解析层只需吸收纠斜后的小残差。这里模拟残差 12px（< 半列宽 20px）。
      final data = <int, Map<String, int>>{
        15: {'早': 7, '晚': 9},
      };
      final lines = _monthLines(
        name: '张三',
        price: 1.2,
        daysInMonth: 31,
        originX: 100,
        dayStep: 40,
        data: data,
        skew: 12,
      );
      final report = MonthlyReportParser.parse(lines, year: 2026, month: 8);
      final e = report.entries.firstWhere((x) => x.workerName == '张三' && x.price == 1.2);
      expect(e.cells.firstWhere((c) => c.day == 15 && c.shift == '早').count, 7);
      expect(e.cells.firstWhere((c) => c.day == 15 && c.shift == '晚').count, 9);
    });
  });
}

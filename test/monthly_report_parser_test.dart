import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/core/util/monthly_report_parser.dart';
import 'package:yard_accounting/domain/entities/ocr_result.dart';

OcrLine _line(String text, double left, double top, {double width = 40}) =>
    OcrLine(text: text, boundingBox: Rect.fromLTRB(left, top, left + width, top + 18));

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
      expect(zhang12.cells.length, 4); // 2 天 × 2 班
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
  });
}

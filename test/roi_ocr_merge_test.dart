import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:yard_accounting/core/util/roi_ocr.dart';
import 'package:yard_accounting/domain/entities/ocr_result.dart';

OcrLine _l(String text, double left, double top, {double w = 40, double h = 18}) =>
    OcrLine(text: text, boundingBox: Rect.fromLTRB(left, top, left + w, top + h));

void main() {
  group('RoiOcr.findNameRows', () {
    const imageWidth = 1000;

    test('只认靠左的 2-4 字中文姓名行', () {
      final zhang = _l('张三', 10, 50);
      final li = _l('李四', 10, 300);
      final wang = _l('王五', 10, 600);
      final lines = [
        _l('早', 200, 10), // 表头，不在姓名列
        _l('1.2元/车', 10, 90), // 单价行，含数字/元，排除
        zhang,
        _l('30', 300, 100), // 数字行，非中文，排除
        _l('合计', 900, 10),
        _l('张三丰', 500, 400), // 靠右，排除
        li,
        wang,
      ];
      final names = RoiOcr.findNameRows(lines, imageWidth);
      expect(names, containsAll([zhang, li, wang]));
      expect(names.length, 3);
    });
  });

  group('RoiOcr.buildBandPlan', () {
    test('相邻姓名之间形成 band，最后一人按图高比例截断', () {
      final zhang = _l('张三', 10, 50, h: 20);
      final li = _l('李四', 10, 300, h: 20);
      final wang = _l('王五', 10, 600, h: 20);
      final plan = RoiOcr.buildBandPlan([zhang, li, wang], 1200);
      expect(plan.length, 3);
      // 张三 band：[70, 300)
      expect(plan[0]['rowIndex'], 0);
      expect(plan[0]['top'], 70);
      expect(plan[0]['bottom'], 300);
      // 李四 band：[320, 600)
      expect(plan[1]['rowIndex'], 1);
      expect(plan[1]['top'], 320);
      expect(plan[1]['bottom'], 600);
      // 王五 band：[620, 620+1200*0.3=980)
      expect(plan[2]['top'], 620);
      expect(plan[2]['bottom'], 980);
    });

    test('重叠/过矮的 band 被跳过，其余不受影响', () {
      final a = _l('张三', 10, 50, h: 20); // bottom=70
      final b = _l('李四', 10, 62, h: 20); // top=62 < 70，重叠，band 无效
      final plan = RoiOcr.buildBandPlan([a, b], 1200);
      // 张三的重叠 band 被跳过，李四作为最后一人仍生成 band
      expect(plan.length, 1);
      expect(plan[0]['rowIndex'], 1);
      expect(plan[0]['top'], 82);
      expect(plan[0]['bottom'], 442);
    });
  });

  group('RoiOcr.mergeBandResults', () {
    final zhang = _l('章三', 10, 50); // OCR 错字，将被姓名条纠正
    final li = _l('李四', 10, 300);
    final wang = _l('王五', 10, 600);

    // 整图结果：表头 + 每人名下数据行
    final headerEarly = _l('早', 200, 10);
    final headerTotal = _l('合计', 900, 10);
    final zhangPrice = _l('1.2元/车', 10, 90);
    final zhangNum = _l('30', 300, 100);
    final liPrice = _l('1.8元/车', 10, 340);
    final liNum = _l('12', 400, 350);
    final wangPrice = _l('5元/车', 10, 640);
    final wangNum = _l('7', 300, 650);

    List<OcrLine> buildFullLines() => [
          headerEarly,
          headerTotal,
          zhang,
          zhangPrice,
          zhangNum,
          li,
          liPrice,
          liNum,
          wang,
          wangPrice,
          wangNum,
        ];

    List<String?> namesOk() => ['张三', '李四', '王五'];

    test('band 有效（含元/车）时替换该段数字，姓名文本被纠正，表头保留', () {
      final band0 = [
        _l('1.2元/车', 10, 80),
        _l('35', 300, 82),
        _l('6', 400, 84),
      ];
      final merged = RoiOcr.mergeBandResults(
        fullLines: buildFullLines(),
        nameRows: [zhang, li, wang],
        nameTexts: namesOk(),
        bandLines: {0: band0},
        imageHeight: 1200,
      );

      final texts = merged.map((l) => l.text).toList();
      // 表头保留
      expect(texts, contains('早'));
      expect(texts, contains('合计'));
      // 姓名被纠正
      expect(texts, contains('张三'));
      expect(texts, isNot(contains('章三')));
      expect(texts, contains('李四'));
      expect(texts, contains('王五'));
      // 张三段原数字行被 band 替换
      expect(texts, isNot(contains('30')));
      expect(texts, contains('35'));
      expect(texts, contains('6'));
      // 其他段（无 band 结果）原样保留
      expect(texts, contains('1.8元/车'));
      expect(texts, contains('12'));
      expect(texts, contains('5元/车'));
      expect(texts, contains('7'));
    });

    test('band 无单价行视为无效，整体回退整图行', () {
      final band0 = [_l('5', 300, 82)]; // 只有数字，没有 元/车
      final merged = RoiOcr.mergeBandResults(
        fullLines: buildFullLines(),
        nameRows: [zhang, li, wang],
        nameTexts: namesOk(),
        bandLines: {0: band0},
        imageHeight: 1200,
      );

      final texts = merged.map((l) => l.text).toList();
      // 张三段整图行全部保留，band 的孤立数字不混入
      expect(texts, contains('1.2元/车'));
      expect(texts, contains('30'));
      expect(texts, isNot(contains('5')));
    });

    test('空 band 结果时所有行原样保留', () {
      final merged = RoiOcr.mergeBandResults(
        fullLines: buildFullLines(),
        nameRows: [zhang, li, wang],
        nameTexts: namesOk(),
        bandLines: const {},
        imageHeight: 1200,
      );
      expect(merged.map((l) => l.text), containsAll(['早', '合计', '张三', '1.2元/车', '30', '李四', '1.8元/车', '12', '王五', '5元/车', '7']));
    });
  });
}

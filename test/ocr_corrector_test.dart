import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/core/util/ocr_corrector.dart';

void main() {
  group('correctOcrText 数字形近纠错', () {
    test('0↔O 纠正', () {
      expect(correctOcrText('12O5'), '1205');
    });

    test('1↔l/I 纠正', () {
      expect(correctOcrText('Il18'), '1118');
    });

    test('5↔S 纠正', () {
      expect(correctOcrText('S30'), '530');
    });

    test('8↔B 纠正', () {
      expect(correctOcrText('B800'), '8800');
    });

    test('全角数字归一为半角', () {
      expect(correctOcrText('１２３４'), '1234');
    });

    test('全角小数点归一为半角', () {
      expect(correctOcrText('12．5'), '12.5');
    });

    test('金额含千分位逗号保持不变', () {
      expect(correctOcrText('1,234.50'), '1,234.50');
    });

    test('纯中文句子不被误改', () {
      expect(correctOcrText('卸车吨数合计'), '卸车吨数合计');
    });

    test('字母占多数（非数字字段）原样保留', () {
      expect(correctOcrText('OIl'), 'OIl');
    });

    test('中文混排金额只纠正数字片段', () {
      expect(correctOcrText('合计吨数: 1O5 吨'), '合计吨数: 105 吨');
    });
  });
}

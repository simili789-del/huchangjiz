import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/core/util/name_matcher.dart';

void main() {
  group('NameMatcher.bestMatch', () {
    final known = ['刘松祥', '王海平', '张三', '李四'];

    test('精确匹配', () {
      expect(NameMatcher.bestMatch('刘松祥', known), '刘松祥');
    });

    test('错一个字（编辑距离 1）纠回', () {
      expect(NameMatcher.bestMatch('刘松样', known), '刘松祥');
    });

    test('漏一个字（子串）纠回', () {
      expect(NameMatcher.bestMatch('刘松', known), '刘松祥');
    });

    test('多一个字纠回', () {
      expect(NameMatcher.bestMatch('刘松祥祥', known), '刘松祥');
    });

    test('带标点不影响', () {
      expect(NameMatcher.bestMatch('王海平.', known), '王海平');
    });

    test('完全不认识返回 null（交给用户手改）', () {
      expect(NameMatcher.bestMatch('赵铁柱', known), isNull);
    });
  });
}

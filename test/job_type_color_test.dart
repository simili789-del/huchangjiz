import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/core/constants/job_types.dart';

void main() {
  group('DefaultJobTypes.colorOf', () {
    test('预定义作业类型颜色保持不变（UI 稳定）', () {
      expect(DefaultJobTypes.colorOf('货场装车'), Colors.blue);
      expect(DefaultJobTypes.colorOf('货场归剁'), Colors.purple);
      expect(DefaultJobTypes.colorOf('外倒装车'), Colors.orange);
      expect(DefaultJobTypes.colorOf('内倒装车'), Colors.red);
      expect(DefaultJobTypes.colorOf('内倒归垛'), Colors.green);
      expect(DefaultJobTypes.colorOf('火车装车'), Colors.brown);
      expect(DefaultJobTypes.colorOf('挖掘机加高'), Colors.teal);
      expect(DefaultJobTypes.colorOf('神华装车'), Colors.indigo);
      expect(DefaultJobTypes.colorOf('神华归垛'), Colors.deepOrange);
      expect(DefaultJobTypes.colorOf('封垛'), Colors.cyan);
    });

    test('未知作业类型自动取色且彼此不撞色', () {
      final a = DefaultJobTypes.colorOf('新作业甲');
      final b = DefaultJobTypes.colorOf('新作业乙');
      final c = DefaultJobTypes.colorOf('新作业丙');
      final d = DefaultJobTypes.colorOf('外倒倒垛');
      // 不同名称应得到不同颜色（区分度）
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
      expect(b, isNot(equals(c)));
      expect(b, isNot(equals(d)));
      expect(c, isNot(equals(d)));
      // 不应退化成统一兜底色（蓝灰）
      expect(a, isNot(equals(Colors.blueGrey)));
      expect(b, isNot(equals(Colors.blueGrey)));
    });

    test('同名作业类型颜色确定稳定（多次调用一致）', () {
      const name = '测试作业类型X';
      expect(DefaultJobTypes.colorOf(name), equals(DefaultJobTypes.colorOf(name)));
    });

    test('大量未知类型取色仍不全部撞色', () {
      final seen = <Color>{};
      for (var i = 0; i < 40; i++) {
        seen.add(DefaultJobTypes.colorOf('自动类型_$i'));
      }
      // 40 个靠哈希分布，去重后仍应有相当数量的不同色（不应全员撞同一色）
      expect(seen.length, greaterThan(10));
    });
  });
}

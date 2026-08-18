import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/data/repositories/excel_importer.dart';
import 'package:yard_accounting/domain/models/imported_row.dart';

/// 验证用户指定的作业类型映射规则：
///   1) 神华装车 / 神华归垛 作为独立作业类型，不并入货场装车 / 货场归剁；
///   2) 外倒装车 已是标准作业类型（原归到货场倒货，现直接用「外倒装车」）；
///   3) 挖掘机「封垛（米）」作为作业类型 封垛，米数即车数（按车算钱）。
void main() {
  const path = 'test/fixtures/job_type_mapping.xlsx';

  test('铲车表：神华装车/神华归垛独立、外倒装车为标准作业类型', () {
    final result = parseXlsx(path, sheetName: '铲车绩效');
    expect(result.importable, isTrue);

    final byName = <String, List<ImportedRow>>{};
    for (final row in result.rows) {
      byName.putIfAbsent(row.workerName, () => []).add(row);
    }

    final zhang = byName['张三']!;
    expect(zhang.length, 1, reason: '张三应解析出一条记录');
    final q = zhang.single.quantities;
    // 外倒装车 即标准作业类型名
    expect(q, containsPair('外倒装车', 5));
    // 神华装车 独立，不再并入货场装车
    expect(q, containsPair('神华装车', 3));
    // 神华归垛 独立，不再并入货场归剁
    expect(q, containsPair('神华归垛', 2));
    // 货场装车 仍是自身
    expect(q, containsPair('货场装车', 10));
    // 关键：不应出现「并入后」的名字
    expect(q.containsKey('货场归剁'), isFalse,
        reason: '神华归垛不应并入货场归剁');
    // 作业类型种类 = 4（货场装车/外倒装车/神华装车/神华归垛）
    expect(q.length, 4);
  });

  test('挖掘机表：封垛（米）作为作业类型封垛，米数值即车数', () {
    final result = parseXlsx(path, sheetName: '挖掘机绩效');
    expect(result.importable, isTrue);

    final byName = <String, List<ImportedRow>>{};
    for (final row in result.rows) {
      byName.putIfAbsent(row.workerName, () => []).add(row);
    }

    final wang = byName['王五']!;
    expect(wang.length, 2, reason: '王五按两条船分两条记录');

    // 两条船的封垛米数分别计入车数（按车算钱）
    final all = <String, int>{};
    for (final r in wang) {
      r.quantities.forEach((k, v) => all[k] = (all[k] ?? 0) + v);
      // 每条都应含「封垛」作业类型，且米数（30 / 15）作为车数
      expect(r.quantities.containsKey('封垛'), isTrue);
    }
    expect(all, containsPair('封垛', 45)); // 30 + 15
    expect(all, containsPair('挖掘机加高', 30)); // 20 + 10

    // 船名正确分条
    final boats = wang.map((r) => r.boatName).toSet();
    expect(boats, containsAll(<String>{'海丰1', '海丰2'}));
  });
}

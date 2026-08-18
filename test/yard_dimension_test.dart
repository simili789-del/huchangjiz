import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:yard_accounting/core/constants/yards.dart';
import 'package:yard_accounting/data/repositories/excel_importer.dart';
import 'package:yard_accounting/data/repositories/record_repository.dart';
import 'package:yard_accounting/domain/models/imported_row.dart';
import 'package:yard_accounting/core/constants/job_types.dart';
import 'package:yard_accounting/domain/entities/work_record.dart';

/// 货场维度改造的专项测试，验证四件事：
/// 1) [Yards.canonicalYard] 能把队长表格里五花八门的货场写法归一成系统标准名；
/// 2) [parseXlsx] 在处理「同一张表上下叠放多张子表」时，能把不同区域正确归属到
///    各自货场（上半 南货场、下半 56道），而不是全表一个货场；
/// 3) [RecordRepository.makeImportId] 把货场 / 班次纳入主键后，同人同天跨货场、
///    跨白班夜班生成互不相同、互不覆盖的钥匙；
/// 4) [RecordRepository.deleteImportedByWorker] 能按（人+日+货场+班次）精确删除一条
///    组合，同时兼容清理升级前的旧格式导入记录，避免重复计。
Future<void> main() async {
  // 第 4 组测试需要 Hive 实箱，复用 widget_test 的纯 Dart 初始化方式
  // （Hive.init + 临时目录，不依赖原生插件）。
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('yard_dim_test_');
    Hive.init(tempDir.path);
    // 注意：生成文件里 WorkRecordAdapter.typeId=0、ShiftTypeAdapter.typeId=1，
    // 守卫检查的类型号必须与各适配器真实 typeId 对应，否则后者会被误判已注册而跳过。
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(WorkRecordAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ShiftTypeAdapter());
    await Hive.openBox<WorkRecord>(HiveBoxes.records);
  });

  group('1. 货场写法归一（canonicalYard）', () {
    test('表/区域标题里的货场关键字被识别', () {
      expect(Yards.canonicalYard('南货场绩效'), '南货场');
      expect(Yards.canonicalYard('56道货场绩效表'), '56道');
      expect(Yards.canonicalYard('挖掘机绩效表（南货场）'), '南货场');
    });

    test('别名关键字归一（含易混的「五六道」「神港」「前场」）', () {
      expect(Yards.canonicalYard('五六道'), '56道');
      expect(Yards.canonicalYard('神港'), '神华');
      expect(Yards.canonicalYard('前场环球倒神华'), '前场'); // 前场优先于神华
      expect(Yards.canonicalYard('45万'), '45万货场');
      expect(Yards.canonicalYard('南27货场'), '27万货场'); // 多字优先，不被「27万」误截
    });

    test('识别不出时返回 null，且不把无关文字误判为货场', () {
      expect(Yards.canonicalYard(''), isNull);
      expect(Yards.canonicalYard('姓名'), isNull);
      expect(Yards.canonicalYard('合计'), isNull);
      expect(Yards.canonicalYard('托6小时'), isNull);
    });
  });

  group('2. 多子表头按区域归属货场（parseXlsx）', () {
    const path = 'test/fixtures/yard_performance_multi_header.xls';

    test('铲车司机绩效：上半区司机归南货场、下半区司机归 56道', () {
      final result = parseXlsx(path);
      expect(result.importable, isTrue);

      final byName = <String, List<ImportedRow>>{};
      for (final row in result.rows) {
        byName.putIfAbsent(row.workerName, () => []).add(row);
      }

      // 董景辉：上半（南货场）+ 下半（56道）各一条，且货场互不串。
      final dong = byName['董景辉']!;
      expect(dong.length, 2, reason: '董景辉应解析出上下两表各一条记录');
      final dongNan = dong.where((r) => r.yard == '南货场').toList();
      final dong56 = dong.where((r) => r.yard == '56道').toList();
      expect(dongNan.length, 1, reason: '上半区记录应归属南货场');
      expect(dong56.length, 1, reason: '下半区记录应归属 56道');
      expect(dongNan.single.quantities, containsPair('货场装车', 2));
      expect(dong56.single.quantities, containsPair('火车装车', 16));

      // 陈登国：仅下半区有车数，应归属 56道。
      final chen = byName['陈登国']!;
      expect(chen.length, 1);
      expect(chen.single.yard, '56道');
      expect(chen.single.quantities, containsPair('神华归垛', 50));
    });

    test('货场段一律非 null/非空前缀（解析层已正确标注）', () {
      final result = parseXlsx(path);
      for (final row in result.rows) {
        expect(row.yard, isNotNull);
        expect(row.yard, isNotEmpty);
      }
    });
  });

  group('3. 货场/班次纳入导入主键（makeImportId）', () {
    final date = DateTime(2026, 7, 7);

    test('同人同天跨货场生成不同钥匙', () {
      final a = RecordRepository.makeImportId(date, '董景辉',
          yard: '南货场', shift: ShiftType.day);
      final b = RecordRepository.makeImportId(date, '董景辉',
          yard: '56道', shift: ShiftType.day);
      expect(a, isNot(equals(b)));
      expect(a, 'imp_2026-07-07_董景辉_南货场_白班');
      expect(b, 'imp_2026-07-07_董景辉_56道_白班');
    });

    test('同人同天同货场跨白班/夜班生成不同钥匙', () {
      final day = RecordRepository.makeImportId(date, '董景辉',
          yard: '南货场', shift: ShiftType.day);
      final night = RecordRepository.makeImportId(date, '董景辉',
          yard: '南货场', shift: ShiftType.night);
      expect(day, isNot(equals(night)));
      expect(night, 'imp_2026-07-07_董景辉_南货场_夜班');
    });

    test('不带货场/班次时回退为向后兼容的裸主键', () {
      final bare = RecordRepository.makeImportId(date, '董景辉');
      expect(bare, 'imp_2026-07-07_董景辉');
      // 船名段仍按船分条
      final boat = RecordRepository.makeImportId(date, '孙同曦', boat: '大周');
      expect(boat, 'imp_2026-07-07_孙同曦_大周');
    });
  });

  group('4. 按组合精确删除并兼容清理旧格式（deleteImportedByWorker）', () {
    final date = DateTime(2026, 7, 7);

    Future<String> seed(String name,
        {String? yard, ShiftType? shift, String? boat}) async {
      final id = RecordRepository.makeImportId(date, name,
          yard: yard, shift: shift, boat: boat);
      final rec = WorkRecord(
        id: id,
        date: date,
        workerName: name,
        vehicleNo: '',
        shift: shift ?? ShiftType.day,
        jobQuantities: const {'货场装车': 1},
        yard: yard,
      );
      final repo = RecordRepository();
      await repo.saveImportedRecords([rec]);
      return id;
    }

    test('只删（人+日+货场+班次）组合，其余货场/班次保留；旧格式一并清掉', () async {
      await Hive.box<WorkRecord>(HiveBoxes.records).clear(); // 隔离：从空箱开始
      // 新格式：同人同天三个组合
      final keep1 = await seed('董景辉', yard: '南货场', shift: ShiftType.day);
      final keep2 = await seed('董景辉', yard: '56道', shift: ShiftType.day);
      final keep3 = await seed('董景辉', yard: '南货场', shift: ShiftType.night);
      // 旧格式（升级前）：裸主键 + 单段船名
      final oldBare = await seed('董景辉'); // imp_..._董景辉
      final oldBoat = await seed('董景辉', boat: '大周'); // imp_..._董景辉_大周

      final repo = RecordRepository();
      // 只删 南货场 + 白班 这一条组合
      await repo.deleteImportedByWorker(date, '董景辉',
          yard: '南货场', shift: ShiftType.day);

      final box = Hive.box<WorkRecord>(HiveBoxes.records);
      // 被删：目标组合 + 两类旧格式
      expect(box.containsKey(keep1), isFalse, reason: '目标组合应被删除');
      expect(box.containsKey(oldBare), isFalse, reason: '旧格式裸主键应被清理');
      expect(box.containsKey(oldBoat), isFalse, reason: '旧格式船名段应被清理');
      // 保留：其他货场 / 其他班次 / 同人同天不串
      expect(box.containsKey(keep2), isTrue, reason: '56道记录应保留');
      expect(box.containsKey(keep3), isTrue, reason: '夜班记录应保留');
    });

    test('不带货场/班次时删除该人当天全部（含新旧格式）', () async {
      await Hive.box<WorkRecord>(HiveBoxes.records).clear(); // 隔离：清掉上一条测试遗留
      final a = await seed('王海军', yard: '南货场', shift: ShiftType.day);
      final b = await seed('王海军', yard: '前场', shift: ShiftType.night);
      final c = await seed('王海军'); // 旧格式裸
      final d = await seed('王海军', boat: '中海顺和'); // 旧格式船名

      final repo = RecordRepository();
      await repo.deleteImportedByWorker(date, '王海军');

      final box = Hive.box<WorkRecord>(HiveBoxes.records);
      expect(box.containsKey(a), isFalse);
      expect(box.containsKey(b), isFalse);
      expect(box.containsKey(c), isFalse);
      expect(box.containsKey(d), isFalse);
    });
  });
}

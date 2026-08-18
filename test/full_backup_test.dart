import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yard_accounting/data/repositories/settings_repository.dart';
import 'package:yard_accounting/data/serialization/record_serialization.dart';
import 'package:yard_accounting/domain/entities/app_settings.dart';
import 'package:yard_accounting/domain/entities/salary_settings.dart';
import 'package:yard_accounting/domain/entities/work_record.dart';

void main() {
  group('FullBackup JSON 全量往返', () {
    final records = [
      WorkRecord(
        id: 'imp_2026-08-01_张三',
        date: DateTime(2026, 8, 1),
        workerName: '张三',
        vehicleNo: '京A1',
        shift: ShiftType.day,
        jobQuantities: {'货场装车': 10, '外倒装车': 5},
        remark: '测试',
      ),
    ];
    final backup = FullBackup(
      records: records,
      jobPrices: {'货场装车': 1.2, '外倒装车': 1.8, '神华装车': 1.5},
      salarySettings: SalarySettings(
        baseSalary: 3000,
        mealAllowance: 300,
        deduction: 100,
        overtime: 200,
        seniorityBonus: 50,
      ),
      appSettings: AppSettings(
        defaultWorkerName: '张三',
        yardName: '测试货场',
        dailyTargetVehicles: 80,
        monthlyTargetVehicles: 2000,
        primaryColorIndex: 2,
        hideAmount: false,
        boatNames: ['船A', '船B'],
      ),
      fixedWorkers: ['张三', '李四'],
      importTemplate: ImportTemplate(
        sheetName: '铲车绩效',
        headerRow: 2,
        rawColumns: ['车号', '姓名', '货场装车'],
      ),
    );

    test('导出 JSON 包含 records 与 settings', () {
      final decoded = jsonDecode(RecordSerialization.toFullBackupJson(backup));
      expect(decoded['version'], 2);
      expect(decoded['records'], isList);
      expect(decoded['settings'], isA<Map>());
      expect(decoded['settings']['jobPrices']['货场装车'], 1.2);
      expect(decoded['settings']['salarySettings']['baseSalary'], 3000);
      expect(decoded['settings']['appSettings']['yardName'], '测试货场');
      expect(decoded['settings']['fixedWorkers'], contains('李四'));
      expect(decoded['settings']['importTemplate']['sheetName'], '铲车绩效');
    });

    test('解析回来后记录与配置完全一致', () {
      final parsed =
          RecordSerialization.parseFullBackup(RecordSerialization.toFullBackupJson(backup));
      expect(parsed.records.length, 1);
      expect(parsed.records.first.workerName, '张三');
      expect(parsed.records.first.jobQuantities['货场装车'], 10);
      expect(parsed.jobPrices,
          equals({'货场装车': 1.2, '外倒装车': 1.8, '神华装车': 1.5}));
      expect(parsed.salarySettings!.baseSalary, 3000);
      expect(parsed.salarySettings!.seniorityBonus, 50);
      expect(parsed.appSettings!.yardName, '测试货场');
      expect(parsed.appSettings!.boatNames, equals(['船A', '船B']));
      expect(parsed.fixedWorkers, equals(['张三', '李四']));
      expect(parsed.importTemplate!.sheetName, '铲车绩效');
      expect(parsed.hasSettings, isTrue);
    });

    test('旧版仅含 records 的备份仍可解析（向后兼容）', () {
      final oldJson = jsonEncode({
        'version': 1,
        'records': [
          {
            'id': 'imp_2026-08-01_王五',
            'date': '2026-08-01T00:00:00.000',
            'workerName': '王五',
            'vehicleNo': '京B2',
            'shift': 'night',
            'jobQuantities': {'货场归剁': 7},
            'remark': null,
            'boatName': null,
          }
        ]
      });
      final parsed = RecordSerialization.parseFullBackup(oldJson);
      expect(parsed.records.length, 1);
      expect(parsed.records.first.workerName, '王五');
      expect(parsed.records.first.shift, ShiftType.night);
      expect(parsed.jobPrices, isNull);
      expect(parsed.hasSettings, isFalse);
    });
  });
}

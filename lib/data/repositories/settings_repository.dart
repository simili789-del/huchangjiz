import 'package:hive/hive.dart';

import '../../core/constants/job_types.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/salary_settings.dart';

/// 导入模板：记住一张固定格式表的「表头行 + 原始列名集合」，
/// 下次导入同格式表时自动识别并提示，免去每次重选列。
class ImportTemplate {
  final String sheetName;
  final int headerRow;
  final List<String> rawColumns;

  ImportTemplate({
    required this.sheetName,
    required this.headerRow,
    required this.rawColumns,
  });

  Map<String, dynamic> toJson() => {
        'sheetName': sheetName,
        'headerRow': headerRow,
        'rawColumns': rawColumns,
      };

  factory ImportTemplate.fromJson(Map<dynamic, dynamic> m) => ImportTemplate(
        sheetName: m['sheetName'] as String,
        headerRow: m['headerRow'] as int,
        rawColumns: List<String>.from(m['rawColumns'] as List),
      );
}

/// 模板指纹：同 sheet + 同原始列集合 即视为同一格式表。
String importTemplateFingerprint(String sheetName, List<String> rawColumns) =>
    '$sheetName||${rawColumns.join('|')}';

/// 设置数据仓库：作业类型单价 + 工资构成 + 主题模式。
class SettingsRepository {
  Box get _priceBox => Hive.box(HiveBoxes.jobPrices);
  Box<SalarySettings> get _salaryBox =>
      Hive.box<SalarySettings>(HiveBoxes.salarySettings);
  Box get _appBox => Hive.box(HiveBoxes.appSettings);
  Box<AppSettings> get _appSettingsBox =>
      Hive.box<AppSettings>(HiveBoxes.appSettingsV2);

  Map<String, double> getUnitPrices() {
    final map = <String, double>{};
    for (final key in _priceBox.keys) {
      map[key as String] = (_priceBox.get(key) as num).toDouble();
    }
    return map;
  }

  Future<void> setUnitPrice(String jobType, double price) async {
    await _priceBox.put(jobType, price);
  }

  Future<void> removeJobType(String jobType) async {
    await _priceBox.delete(jobType);
  }

  /// 整体替换作业类型单价（恢复备份时调用）：清空后写入，保证与备份一致。
  Future<void> replaceAllPrices(Map<String, double> prices) async {
    await _priceBox.clear();
    for (final entry in prices.entries) {
      await _priceBox.put(entry.key, entry.value);
    }
  }

  SalarySettings getSalarySettings() {
    return _salaryBox.get('current') ?? SalarySettings();
  }

  Future<void> saveSalarySettings(SalarySettings settings) async {
    await _salaryBox.put('current', settings);
  }

  /// 全局应用设置（v2 新 box）。
  AppSettings getAppSettings() {
    return _appSettingsBox.get('current') ?? AppSettings();
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    await _appSettingsBox.put('current', settings);
  }

  /// 主题模式：'light' / 'dark' / 'system'
  String getThemeMode() => _appBox.get('themeMode', defaultValue: 'system');

  Future<void> setThemeMode(String mode) async {
    await _appBox.put('themeMode', mode);
  }

  /// 「固定人员名单」：导入向导预勾用，避免每次手动勾选。
  List<String> getFixedWorkers() =>
      List<String>.from(_appBox.get('fixedWorkers', defaultValue: <String>[]));

  Future<void> setFixedWorkers(List<String> workers) async {
    await _appBox.put('fixedWorkers', workers);
  }

  /// 「导入模板」：记住常用表格的列结构，下次自动套用。
  ImportTemplate? getImportTemplate() {
    final m = _appBox.get('importTemplate');
    if (m == null) return null;
    try {
      return ImportTemplate.fromJson(Map<String, dynamic>.from(m as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveImportTemplate(ImportTemplate template) async {
    await _appBox.put('importTemplate', template.toJson());
  }
}

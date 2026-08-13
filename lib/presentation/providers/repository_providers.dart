import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/salary_settings.dart';

final recordRepositoryProvider = Provider<RecordRepository>((ref) {
  return RecordRepository();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// 作业类型单价列表（响应式）：设置页增删改后，首页/统计页自动刷新
final unitPricesProvider =
    StateNotifierProvider<UnitPricesNotifier, Map<String, double>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return UnitPricesNotifier(repo);
});

class UnitPricesNotifier extends StateNotifier<Map<String, double>> {
  final SettingsRepository _repo;
  UnitPricesNotifier(this._repo) : super(_repo.getUnitPrices());

  void refresh() {
    state = _repo.getUnitPrices();
  }

  void setPrice(String jobType, double price) {
    _repo.setUnitPrice(jobType, price);
    state = Map<String, double>.from(state)..[jobType] = price;
  }

  void remove(String jobType) {
    _repo.removeJobType(jobType);
    state = Map<String, double>.from(state)..remove(jobType);
  }

  /// 重命名作业类型：保留原单价，旧名删除、新名写入。
  void rename(String oldName, String newName) {
    if (oldName == newName) return;
    final price = state[oldName] ?? 1.0;
    _repo.setUnitPrice(newName, price);
    _repo.removeJobType(oldName);
    final next = Map<String, double>.from(state);
    next.remove(oldName);
    next[newName] = price;
    state = next;
  }

  void add(String jobType, double price) {
    _repo.setUnitPrice(jobType, price);
    state = Map<String, double>.from(state)..[jobType] = price;
  }
}

/// 工资构成设置（响应式）
final salarySettingsProvider =
    StateNotifierProvider<SalarySettingsNotifier, SalarySettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return SalarySettingsNotifier(repo);
});

class SalarySettingsNotifier extends StateNotifier<SalarySettings> {
  final SettingsRepository _repo;
  SalarySettingsNotifier(this._repo) : super(_repo.getSalarySettings());

  void update(SalarySettings settings) {
    _repo.saveSalarySettings(settings);
    state = settings;
  }
}

/// 主题模式状态（浅色/深色/跟随系统），供 MaterialApp 与设置页共用。
final themeModeProvider = StateProvider<String>((ref) {
  return ref.read(settingsRepositoryProvider).getThemeMode();
});

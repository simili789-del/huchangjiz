import 'package:flutter/foundation.dart';
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

  /// 先乐观更新内存、再落盘；落盘失败时 refresh() 回滚乐观更新。
  Future<void> _persist(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      debugPrint('作业类型单价写入失败: $e');
      refresh();
    }
  }

  void refresh() {
    state = _repo.getUnitPrices();
  }

  Future<void> setPrice(String jobType, double price) async {
    state = Map<String, double>.from(state)..[jobType] = price;
    await _persist(() => _repo.setUnitPrice(jobType, price));
  }

  Future<void> remove(String jobType) async {
    state = Map<String, double>.from(state)..remove(jobType);
    await _persist(() => _repo.removeJobType(jobType));
  }

  /// 重命名作业类型：保留原单价，旧名删除、新名写入。
  Future<void> rename(String oldName, String newName) async {
    if (oldName == newName) return;
    final price = state[oldName] ?? 1.0;
    state = (Map<String, double>.from(state)
      ..remove(oldName)
      ..[newName] = price);
    await _persist(() async {
      await _repo.setUnitPrice(newName, price);
      await _repo.removeJobType(oldName);
    });
  }

  Future<void> add(String jobType, double price) async {
    if (state.containsKey(jobType)) {
      throw Exception('作业类型「$jobType」已存在');
    }
    state = Map<String, double>.from(state)..[jobType] = price;
    await _persist(() => _repo.setUnitPrice(jobType, price));
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import 'repository_providers.dart';

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return AppSettingsNotifier(repo);
});

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository _repo;

  AppSettingsNotifier(this._repo) : super(_repo.getAppSettings());

  void update(AppSettings settings) {
    _repo.saveAppSettings(settings);
    state = settings;
  }

  void updateDefaultWorkerName(String value) =>
      update(state.copyWith(defaultWorkerName: value));

  void updateDefaultVehicleNo(String value) =>
      update(state.copyWith(defaultVehicleNo: value));

  void updateYardName(String value) =>
      update(state.copyWith(yardName: value));

  void updateDailyTarget(int value) =>
      update(state.copyWith(dailyTargetVehicles: value));

  void updateMonthlyTarget(int value) =>
      update(state.copyWith(monthlyTargetVehicles: value));

  void updatePrimaryColorIndex(int index) =>
      update(state.copyWith(primaryColorIndex: index));

  void updateHideAmount(bool value) =>
      update(state.copyWith(hideAmount: value));

  void updateBoatNames(List<String> value) =>
      update(state.copyWith(boatNames: value));

  /// 导入时调用：把命中的非常用类型并入已解锁集合（并集，不丢已有）。
  void revealAdvancedTypes(Set<String> types) {
    final merged = {...state.revealedAdvancedTypes, ...types};
    update(state.copyWith(revealedAdvancedTypes: merged.toList()));
  }

  /// 手动入口调用：勾选=显示，取消=隐藏。
  void setAdvancedTypeVisible(String type, bool visible) {
    final set = {...state.revealedAdvancedTypes};
    if (visible) {
      set.add(type);
    } else {
      set.remove(type);
    }
    update(state.copyWith(revealedAdvancedTypes: set.toList()));
  }

  /// 普通/手动添加作业类型的显隐：hidden=true 则从首页常规区隐藏，false 恢复显示。
  void setJobTypeHidden(String type, bool hidden) {
    final set = {...state.hiddenJobTypes};
    if (hidden) {
      set.add(type);
    } else {
      set.remove(type);
    }
    update(state.copyWith(hiddenJobTypes: set.toList()));
  }
}

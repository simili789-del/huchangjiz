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
}

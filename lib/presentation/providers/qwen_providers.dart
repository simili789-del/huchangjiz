import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/qwen_vl_ocr_engine.dart';
import '../../data/repositories/secure_settings_repository.dart';

/// Secure settings 单例仓库。
final secureSettingsRepositoryProvider =
    Provider<SecureSettingsRepository>((ref) => SecureSettingsRepository());

/// 当前配置的 API Key（异步从 secure storage 读）。
/// null = 未配置；非空 = 已配置。
final qwenApiKeyProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(secureSettingsRepositoryProvider);
  return repo.getApiKey();
});

/// 当前配置的 Base URL + 模型（异步从 secure storage 读）。
class QwenConfig {
  final String baseUrl;
  final String model;
  const QwenConfig({required this.baseUrl, required this.model});
}

final qwenConfigProvider = FutureProvider<QwenConfig>((ref) async {
  final repo = ref.watch(secureSettingsRepositoryProvider);
  return QwenConfig(
    baseUrl: await repo.getBaseUrl(),
    model: await repo.getModel(),
  );
});

/// Qwen-VL 引擎实例：仅当 API Key 已配置时构造，否则抛错。
/// 配合 `qwenVlEngineOrNullProvider` 在 UI 层安全判空。
final qwenVlEngineProvider = FutureProvider<QwenVlOcrEngine>((ref) async {
  final repo = ref.watch(secureSettingsRepositoryProvider);
  final apiKey = await repo.getApiKey();
  if (apiKey == null || apiKey.isEmpty) {
    throw StateError('Qwen API Key 未配置，请到「设置 → 云端识别」配置');
  }
  return QwenVlOcrEngine(
    apiKey: apiKey,
    baseUrl: await repo.getBaseUrl(),
    model: await repo.getModel(),
  );
});

/// 安全获取：API Key 未配置时返回 null（用于对账页「高精度」开关的判空）。
final qwenVlEngineOrNullProvider = FutureProvider<QwenVlOcrEngine?>((ref) async {
  final repo = ref.watch(secureSettingsRepositoryProvider);
  final apiKey = await repo.getApiKey();
  if (apiKey == null || apiKey.isEmpty) return null;
  return QwenVlOcrEngine(
    apiKey: apiKey,
    baseUrl: await repo.getBaseUrl(),
    model: await repo.getModel(),
  );
});

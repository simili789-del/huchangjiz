import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 加密设置仓库：用 Android Keystore 加密存 API Key / 模型名等敏感配置。
///
/// 卸载 App 即清空，root 设备也难拿到明文。
class SecureSettingsRepository {
  SecureSettingsRepository({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kApiKey = 'qwen_api_key';
  static const _kBaseUrl = 'qwen_base_url';
  static const _kModel = 'qwen_model';

  static const defaultBaseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
  static const defaultModel = 'qwen-vl-plus';

  Future<String?> getApiKey() => _storage.read(key: _kApiKey);
  Future<void> setApiKey(String value) => _storage.write(key: _kApiKey, value: value);
  Future<void> clearApiKey() => _storage.delete(key: _kApiKey);

  Future<String> getBaseUrl() async =>
      (await _storage.read(key: _kBaseUrl)) ?? defaultBaseUrl;
  Future<void> setBaseUrl(String value) => _storage.write(key: _kBaseUrl, value: value);

  Future<String> getModel() async =>
      (await _storage.read(key: _kModel)) ?? defaultModel;
  Future<void> setModel(String value) => _storage.write(key: _kModel, value: value);

  /// 一次性保存三项配置（设置页"保存"按钮触发）。
  Future<void> saveAll({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    await setApiKey(apiKey);
    await setBaseUrl(baseUrl);
    await setModel(model);
  }
}

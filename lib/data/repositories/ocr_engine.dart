import '../../domain/entities/ocr_result.dart';

/// OCR 引擎抽象：支持离线 ML Kit 与可选云端高精度双引擎。
///
/// 使用方式：
/// - 默认 [OcrEngineMode.offline] → ML Kit 中文离线
/// - 用户打开「高精度识别」开关 → [OcrEngineMode.cloud]（需实现 CloudOcrEngine）
abstract class OcrEngine {
  /// 识别图片，返回带坐标的文本行。
  Future<List<OcrLine>> recognize(String imagePath);

  /// 释放资源。
  void dispose();
}

/// 引擎模式。
enum OcrEngineMode {
  /// 离线 ML Kit（默认，无网络、免费）。
  offline,

  /// 云端高精度表格 OCR（需联网、可选接入百度/腾讯等）。
  cloud,
}

/// 双引擎门面：根据 [mode] 路由到具体实现。
///
/// 云端引擎未配置时自动降级到离线，保证功能可用。
class DualOcrEngine implements OcrEngine {
  DualOcrEngine({
    required OcrEngine offline,
    OcrEngine? cloud,
    this.mode = OcrEngineMode.offline,
  })  : _offline = offline,
        _cloud = cloud;

  final OcrEngine _offline;
  final OcrEngine? _cloud;
  OcrEngineMode mode;

  OcrEngine get _active {
    if (mode == OcrEngineMode.cloud && _cloud != null) return _cloud;
    return _offline;
  }

  @override
  Future<List<OcrLine>> recognize(String imagePath) =>
      _active.recognize(imagePath);

  @override
  void dispose() {
    _offline.dispose();
    _cloud?.dispose();
  }
}

/// 云端 OCR 引擎占位实现。
///
/// 接入时替换 [recognize] 内部逻辑，调用百度/腾讯/华为表格 OCR API，
/// 把返回的文字块映射为 [OcrLine]（尽量带 boundingBox）。
///
/// 示例（百度通用文字高精度）：
/// ```dart
/// final resp = await baiduOcr.basicGeneral(imageBytes);
/// return resp.wordsResult.map((w) => OcrLine(
///   text: w.words,
///   boundingBox: Rect.fromLTRB(...),
/// )).toList();
/// ```
class CloudOcrEngine implements OcrEngine {
  /// API Key / Secret 等由调用方注入，不要硬编码进仓库。
  final String? apiKey;
  final String? secretKey;

  /// 实际 HTTP 调用函数，便于测试与替换。
  final Future<List<OcrLine>> Function(String imagePath)? client;

  CloudOcrEngine({this.apiKey, this.secretKey, this.client});

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    if (client != null) return client!(imagePath);
    // 未配置时抛出明确错误，由上层捕获并降级。
    throw StateError(
      'CloudOcrEngine 未配置 client。请接入百度/腾讯表格 OCR 后注入 client 回调。',
    );
  }

  @override
  void dispose() {}
}

import '../../domain/entities/monthly_report.dart';
import '../../domain/entities/ocr_result.dart';

/// OCR 引擎抽象：支持离线 ML Kit 与云端高精度双引擎。
///
/// 使用方式：
/// - 默认 [OcrEngineMode.offline] → ML Kit 中文离线
/// - 用户打开「高精度识别」开关 → [OcrEngineMode.cloud]（需实现 QwenVlOcrEngine）
abstract class OcrEngine {
  /// 识别图片，返回带坐标的文本行（行级 OCR，老路径，离线 ML Kit 用）。
  Future<List<OcrLine>> recognize(String imagePath);

  /// 云端直出结构化月报（高准确率路径）。
  /// 离线引擎默认返回 null；QwenVlOcrEngine 实现此方法。
  /// 返回 null 表示该引擎不支持结构化直出，调用方应降级到 [recognize] + 行级解析。
  Future<MonthlyReport?> recognizeStructured(String imagePath) async => null;

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
  OcrEngine? _cloud;
  OcrEngineMode mode;

  /// 云端引擎是否已配置（供 OcrRepository 判断是否走云端结构化路径）。
  bool get hasCloud => _cloud != null;

  /// 运行时设置/替换云端引擎（secure storage 异步加载完成后挂载）。
  set cloud(OcrEngine? engine) => _cloud = engine;

  OcrEngine? get _active {
    if (mode == OcrEngineMode.cloud && _cloud != null) return _cloud;
    return _offline;
  }

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    final engine = _active;
    if (engine == null) {
      // 云端模式但未注入引擎：降级离线
      return _offline.recognize(imagePath);
    }
    return engine.recognize(imagePath);
  }

  @override
  Future<MonthlyReport?> recognizeStructured(String imagePath) async {
    // 只在云端引擎可用时尝试；离线引擎返回 null（基类默认）。
    if (mode == OcrEngineMode.cloud && _cloud != null) {
      return _cloud!.recognizeStructured(imagePath);
    }
    return null;
  }

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
  Future<MonthlyReport?> recognizeStructured(String imagePath) async => null;

  @override
  void dispose() {}
}

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/util/image_preprocessor.dart';
import '../../core/util/ocr_corrector.dart';
import '../../core/util/roi_ocr.dart';
import '../../domain/entities/monthly_report.dart';
import '../../domain/entities/ocr_result.dart';
import 'ocr_engine.dart';

/// ML Kit 离线引擎实现。
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(input);
    final lines = <OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        lines.add(OcrLine(text: line.text, boundingBox: line.boundingBox));
      }
    }
    return lines;
  }

  @override
  Future<MonthlyReport?> recognizeStructured(String imagePath) async => null;

  @override
  void dispose() => _recognizer.close();
}

/// 离线 OCR 封装（默认）+ 可选云端 + ROI 二次识别。
///
/// 流程：
/// 1. 图像预处理（高分辨率、锐化、自适应对比、绿底抑制、纠斜）
/// 2. 主引擎识别（离线 ML Kit 或云端）
///    - 云端模式优先尝试 [OcrEngine.recognizeStructured]（Qwen-VL 直出 JSON），
///      命中则跳过纠错/ROI/解析器，accuracy 最高且节省云端费用
///    - 否则走行级 [OcrEngine.recognize]
/// 3. 数字形近纠错（仅行级路径）
/// 4. ROI 二次识别（仅行级路径 + 离线引擎，避免云端费用翻倍）
class OcrRepository {
  OcrRepository({
    OcrEngine? offlineEngine,
    OcrEngine? cloudEngine,
    this.mode = OcrEngineMode.offline,
    this.enableRoi = true,
  }) : _engine = DualOcrEngine(
          offline: offlineEngine ?? MlKitOcrEngine(),
          cloud: cloudEngine,
          mode: mode,
        );

  final DualOcrEngine _engine;

  /// 当前引擎模式（可运行时切换）。
  OcrEngineMode mode;

  /// 是否启用 ROI 二次识别（密集表格建议开启，耗时会增加）。
  bool enableRoi;

  /// 最近一次云端调用的错误信息（UI 可读取用于 snackbar 提示）。失败自动降级离线。
  String? lastCloudError;

  /// 运行时注入/替换云端引擎（用于 secure storage 异步加载完成后挂载）。
  void setCloudEngine(OcrEngine? engine) {
    _engine.cloud = engine;
  }

  Future<OcrRecognition> recognize(String imagePath) async {
    // 同步 mode 到双引擎门面
    _engine.mode = mode;
    lastCloudError = null;

    // 1. 预处理（compute 调度到后台 isolate，密集像素运算不阻塞 UI 线程）
    final tempDir = (await getTemporaryDirectory()).path;
    final preMap = await compute(
      preprocessInIsolate,
      <String, dynamic>{'inputPath': imagePath, 'tempDir': tempDir},
    );
    final pre = PreprocessResult.fromMap(preMap);

    // 2. 主引擎识别
    // 2a. 云端模式优先走结构化直出（accuracy 最高路径）
    if (mode == OcrEngineMode.cloud && _engine.hasCloud) {
      try {
        final structured = await _engine.recognizeStructured(pre.processedPath);
        if (structured != null) {
          return OcrRecognition(
            processedImagePath: pre.processedPath,
            lines: const [],
            sharpness: pre.sharpness,
            blurry: pre.blurry,
            imageWidth: pre.width,
            imageHeight: pre.height,
            structuredReport: structured,
          );
        }
        // structured == null：引擎不支持结构化（如旧 CloudOcrEngine 占位），
        // 自动降级走行级 + 切到 offline 模式避免重复失败。
        lastCloudError = '云端引擎未返回结构化数据，已降级离线';
      } catch (e) {
        lastCloudError = _friendlyCloudError(e);
        // 继续降级
      }
      // 降级：切回 offline 跑行级
      _engine.mode = OcrEngineMode.offline;
    }

    // 2b. 行级识别（离线 ML Kit 或旧云端占位）
    List<OcrLine> lines;
    try {
      lines = await _engine.recognize(pre.processedPath);
    } catch (e) {
      if (_engine.mode == OcrEngineMode.cloud) {
        _engine.mode = OcrEngineMode.offline;
        lines = await _engine.recognize(pre.processedPath);
      } else {
        rethrow;
      }
    }

    // 3. 数字形近纠错
    lines = correctOcrLines(lines);

    // 4. ROI 二次识别（仅当图片尺寸有效且开启时；云端模式不重做以省费用）
    if (enableRoi && pre.width > 0 && pre.height > 0 && _engine.mode == OcrEngineMode.offline) {
      try {
        // ROI 内部用离线引擎，避免云端费用翻倍
        final offline = MlKitOcrEngine();
        try {
          lines = await RoiOcr.refine(
            fullLines: lines,
            imagePath: pre.processedPath,
            engine: offline,
            imageWidth: pre.width,
            imageHeight: pre.height,
          );
          // ROI 结果再做一次数字纠错
          lines = correctOcrLines(lines);
        } finally {
          offline.dispose();
        }
      } catch (_) {
        // ROI 失败不影响主结果
      }
    }

    return OcrRecognition(
      processedImagePath: pre.processedPath,
      lines: lines,
      sharpness: pre.sharpness,
      blurry: pre.blurry,
      imageWidth: pre.width,
      imageHeight: pre.height,
    );
  }

  String _friendlyCloudError(Object e) {
    final s = e.toString();
    if (s.contains('401') || s.contains('403')) return 'API Key 无效，请到「设置 → 云端识别」检查';
    if (s.contains('429')) return '调用频率超限，稍后重试';
    if (s.contains('TimeoutException') || s.contains('timeout')) return '云端识别超时，已降级离线';
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return '网络异常，已降级离线';
    }
    return '云端识别失败：$s';
  }

  void dispose() => _engine.dispose();
}

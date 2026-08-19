import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/util/image_preprocessor.dart';
import '../../core/util/ocr_corrector.dart';
import '../../core/util/roi_ocr.dart';
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
  void dispose() => _recognizer.close();
}

/// 离线 OCR 封装（默认）+ 可选云端 + ROI 二次识别。
///
/// 流程：
/// 1. 图像预处理（高分辨率、锐化、自适应对比、绿底抑制、纠斜）
/// 2. 主引擎识别（离线 ML Kit 或云端）
/// 3. 数字形近纠错
/// 4. ROI 二次识别（姓名列 + 数字区裁剪放大再认）—— 可通过 [enableRoi] 关闭
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

  Future<OcrRecognition> recognize(String imagePath) async {
    // 同步 mode 到双引擎门面
    _engine.mode = mode;

    // 1. 预处理（compute 调度到后台 isolate，密集像素运算不阻塞 UI 线程）
    final tempDir = (await getTemporaryDirectory()).path;
    final preMap = await compute(
      preprocessInIsolate,
      <String, dynamic>{'inputPath': imagePath, 'tempDir': tempDir},
    );
    final pre = PreprocessResult.fromMap(preMap);

    // 2. 主引擎识别
    List<OcrLine> lines;
    try {
      lines = await _engine.recognize(pre.processedPath);
    } catch (e) {
      // 云端失败自动降级离线
      if (mode == OcrEngineMode.cloud) {
        _engine.mode = OcrEngineMode.offline;
        lines = await _engine.recognize(pre.processedPath);
      } else {
        rethrow;
      }
    }

    // 3. 数字形近纠错
    lines = correctOcrLines(lines);

    // 4. ROI 二次识别（仅当图片尺寸有效且开启时）
    if (enableRoi && pre.width > 0 && pre.height > 0) {
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

  void dispose() => _engine.dispose();
}

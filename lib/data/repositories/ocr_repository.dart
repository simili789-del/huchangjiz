import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/util/image_preprocessor.dart';
import '../../core/util/ocr_corrector.dart';
import '../../domain/entities/ocr_result.dart';

/// 离线 OCR 封装（google_mlkit_text_recognition，中文模型打包装，图不出手机）。
///
/// 识别会计月报：中文表头 + 数字格子。识别前先做图像增强（转正/放大/纠斜/提对比），
/// 从源头降低错别字与漏识别；中文识别器同时能识别阿拉伯数字，一张图整体识别后，
/// 按 block → line 扁平化为 [OcrLine] 列表，再做数字字段形近纠错后交给上层。
class OcrRepository {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  Future<OcrRecognition> recognize(String imagePath) async {
    // 1. OCR 前图像增强（转正/放大/纠斜/提对比），提升识别准确率。
    //    预处理失败会自动回退到原图，不影响后续识别。
    final pre = await ImagePreprocessor.preprocess(imagePath);

    // 2. ML Kit 中文识别（增强后的图）。
    final input = InputImage.fromFilePath(pre.processedPath);
    final recognized = await _recognizer.processImage(input);

    final lines = <OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        lines.add(OcrLine(text: line.text, boundingBox: line.boundingBox));
      }
    }

    // 3. 后处理：纠正数字 / 金额字段的形近误识（0↔O、1↔l、5↔S、8↔B 等），
    //    提升对账关键数值的准确性。坐标框保持不变。
    final corrected = correctOcrLines(lines);

    return OcrRecognition(
      processedImagePath: pre.processedPath,
      lines: corrected,
      sharpness: pre.sharpness,
      blurry: pre.blurry,
    );
  }

  /// 释放底层本地模型资源（应用退出时由 provider 的 onDispose 调用）。
  void dispose() => _recognizer.close();
}

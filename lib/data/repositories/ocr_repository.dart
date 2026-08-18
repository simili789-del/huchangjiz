import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/entities/ocr_result.dart';

/// 离线 OCR 封装（google_mlkit_text_recognition，中文模型打包装，图不出手机）。
///
/// 识别会计月报：中文表头 + 数字格子。中文识别器同时能识别阿拉伯数字，
/// 一张图整体识别后，按 block → line 扁平化为 [OcrLine] 列表交给上层。
class OcrRepository {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

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

  /// 释放底层本地模型资源（应用退出时由 provider 的 onDispose 调用）。
  void dispose() => _recognizer.close();
}

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';

/// OCR 前图像预处理结果。
///
/// [processedPath] 为增强后的图片路径（既用于 OCR，也用于界面展示）；
/// [sharpness] 是清晰度评分（0~1，越大越清晰）；[blurry] 是否疑似模糊。
class PreprocessResult {
  final String processedPath;
  final double sharpness;
  final bool blurry;

  PreprocessResult({
    required this.processedPath,
    required this.sharpness,
    required this.blurry,
  });
}

/// 拍照/相册图片的 OCR 前增强管道。
///
/// 目标：从源头提升识别准确率。手机拍印刷表格常见问题是「歪斜、昏暗、模糊、
/// 像素偏低」——这些都会让 ML Kit 错别字变多、甚至漏识别数字。依次做：
///   1. 按 EXIF 朝向转正（手机横拍竖排最常见）；
///   2. 小图放大到合适分辨率（ML Kit 对较高分辨率更友好）；
///   3. 轻量纠斜（投影方差估计 ±8° 内的小角度并旋转）；
///   4. 对比度拉伸 + 轻微提亮（弱光下表头/数字更清晰）；
///   5. 清晰度评分（拉普拉斯方差），供 UI 判断是否提示重拍。
///
/// 任何一步异常都会回退到原图，保证 OCR 不会因预处理而失败。
class ImagePreprocessor {
  /// 模糊告警阈值（拉普拉斯方差归一化后的下限）。设得保守，只在明显模糊时报。
  static const double _blurThreshold = 0.06;

  /// 对图片做 OCR 前增强，返回处理后路径与清晰度信息。
  static Future<PreprocessResult> preprocess(String inputPath) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      final decoded = decodeImage(bytes);
      if (decoded == null) {
        // 解码失败（极少见）：回退原图。
        return PreprocessResult(
            processedPath: inputPath, sharpness: 1.0, blurry: false);
      }

      var img = _applyOrientation(decoded);

      // 2. 小图放大（限制上限避免处理过慢）。
      if (img.width < 1280) {
        final scale = (1440 / img.width).clamp(1.0, 2.0);
        img = _resize(img, (img.width * scale).round());
      }

      // 3. 纠斜：估计小角度并旋转。
      final angle = _estimateSkew(img);
      if (angle.abs() > 0.3) {
        img = copyRotate(img, angle: angle, interpolation: Interpolation.cubic);
      }

      // 4. 对比度增强 + 轻微提亮。
      img = adjustColor(img, contrast: 1.3, brightness: 1.06, gamma: 0.92);

      // 5. 清晰度评分。
      final sharpness = _estimateSharpness(img);

      // 6. 编码为临时 JPEG 供 OCR 与展示。
      final outBytes = encodeJpg(img, quality: 88);
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/ocr_pre_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(outBytes);

      return PreprocessResult(
        processedPath: outPath,
        sharpness: sharpness,
        blurry: sharpness < _blurThreshold,
      );
    } catch (_) {
      // 预处理异常：回退原图，不让 OCR 失败。
      return PreprocessResult(
          processedPath: inputPath, sharpness: 1.0, blurry: false);
    }
  }

  /// 按 EXIF 朝向把图片转正。
  static Image _applyOrientation(Image img) {
    try {
      final o = img.exif.imageIfd.orientation;
      if (o == null || o == 1) return img;
      switch (o) {
        case 3:
          return copyRotate(img, angle: 180);
        case 6:
          return copyRotate(img, angle: 90);
        case 8:
          return copyRotate(img, angle: -90);
        case 2:
          return copyFlip(img, direction: FlipDirection.horizontal);
        case 4:
          return copyFlip(img, direction: FlipDirection.vertical);
        case 5:
          return copyFlip(copyRotate(img, angle: 90),
              direction: FlipDirection.horizontal);
        case 7:
          return copyFlip(copyRotate(img, angle: -90),
              direction: FlipDirection.horizontal);
        default:
          return img;
      }
    } catch (_) {
      return img;
    }
  }

  /// 等比缩放到指定宽度（保持长宽比）。
  static Image _resize(Image img, int width) {
    final height = (img.height * width / img.width).round();
    return copyResize(img,
        width: width, height: height, interpolation: Interpolation.average);
  }

  /// 估计倾斜角（度）：在缩小灰度图上扫描候选角度，取「行投影方差」最大的角度。
  ///
  /// 倾斜会让文本跨行、行投影方差变小；正位时文本成行、方差最大。先以 1° 粗扫
  /// ±8°，再在最佳角度附近以 0.5° 细化。
  static double _estimateSkew(Image img) {
    final gray = grayscale(_resize(img, 360));
    double best = 0, bestVar = -1;

    for (double a = -8; a <= 8; a += 1) {
      final v = _rowProjectionVariance(copyRotate(gray, angle: a));
      if (v > bestVar) {
        bestVar = v;
        best = a;
      }
    }
    final coarse = best;
    for (double a = coarse - 1.5; a <= coarse + 1.5; a += 0.5) {
      if ((a - coarse).abs() < 1e-6) continue;
      final v = _rowProjectionVariance(copyRotate(gray, angle: a));
      if (v > bestVar) {
        bestVar = v;
        best = a;
      }
    }
    return best;
  }

  /// 行投影方差：每行暗像素计数作为一维信号，返回其方差。
  static double _rowProjectionVariance(Image g) {
    final h = g.height, w = g.width;
    if (h < 2) return 0;
    final counts = Float64List(h);
    for (int y = 0; y < h; y++) {
      int dark = 0;
      for (int x = 0; x < w; x++) {
        if (g.getPixel(x, y).luminance < 128) dark++;
      }
      counts[y] = dark.toDouble();
    }
    double mean = 0;
    for (int y = 0; y < h; y++) {
      mean += counts[y];
    }
    mean /= h;
    double varSum = 0;
    for (int y = 0; y < h; y++) {
      final d = counts[y] - mean;
      varSum += d * d;
    }
    return varSum / h;
  }

  /// 清晰度评分（0~1）：拉普拉斯（水平+垂直）方差归一化。
  ///
  /// 模糊图的边缘被抹平，拉普拉斯响应弱、方差小；清晰图方差大。
  static double _estimateSharpness(Image img) {
    final gray = grayscale(_resize(img, 320));
    final w = gray.width, h = gray.height;
    if (w < 3 || h < 3) return 1.0;
    double sum = 0, sumSq = 0;
    var n = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = gray.getPixel(x, y).luminance;
        final up = gray.getPixel(x, y - 1).luminance;
        final down = gray.getPixel(x, y + 1).luminance;
        final left = gray.getPixel(x - 1, y).luminance;
        final right = gray.getPixel(x + 1, y).luminance;
        final lap =
            (2 * c - up - down).abs() + (2 * c - left - right).abs();
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    final mean = sum / n;
    final variance = (sumSq / n) - mean * mean;
    // 归一化到 0~1（拉普拉斯幅值量级约 255*2）。
    final norm = sqrt(variance) / (255 * 2);
    return norm.clamp(0, 1);
  }
}

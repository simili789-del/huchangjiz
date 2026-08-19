import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';

/// OCR 前图像预处理结果。
class PreprocessResult {
  final String processedPath;
  final double sharpness;
  final bool blurry;

  /// 处理后的图片宽度（供解析层做相对坐标换算）。
  final int width;

  /// 处理后的图片高度。
  final int height;

  PreprocessResult({
    required this.processedPath,
    required this.sharpness,
    required this.blurry,
    required this.width,
    required this.height,
  });

  /// 序列化为可跨 isolate 传递的 Map（compute 要求基本类型）。
  Map<String, dynamic> toMap() => {
        'processedPath': processedPath,
        'sharpness': sharpness,
        'blurry': blurry,
        'width': width,
        'height': height,
      };

  /// 从 Map 还原（与 [toMap] 配对）。
  factory PreprocessResult.fromMap(Map<String, dynamic> m) => PreprocessResult(
        processedPath: m['processedPath'] as String,
        sharpness: (m['sharpness'] as num).toDouble(),
        blurry: m['blurry'] as bool,
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
      );
}

/// 拍照/相册图片的 OCR 前增强管道（针对货场月报密集表格优化）。
///
/// 增强点（相对旧版）：
///   1. 短边放大到 ≥1600（宽表目标宽 ≥2400），小字信息量显著提升；
///   2. Unsharp Mask 锐化，边缘更清晰；
///   3. 自适应对比度拉伸（百分位裁剪）替代固定 contrast；
///   4. 绿底高亮格对比度补偿；
///   5. 纠斜范围扩大到 ±12°，细化步长 0.5°；
///   6. JPEG quality 92，减少压缩伪影；
///   7. 返回宽高，供解析层做相对坐标。
///
/// **卡顿修复**：所有密集像素运算（自适应对比、锐化、绿底补偿、纠斜、清晰度
/// 评分）都在 [_runSync] 里同步执行，由上层通过 [preprocessInIsolate] + `compute`
/// 调度到后台 isolate，主线程不再被阻塞，导入图片时界面保持流畅。
class ImagePreprocessor {
  /// 模糊告警阈值（拉普拉斯方差归一化后的下限）。
  static const double _blurThreshold = 0.05;

  /// 目标短边最小像素（密集表格需要更高分辨率）。
  static const int _minShortSide = 1600;

  /// 目标长边上限，防止内存爆炸。
  static const int _maxLongSide = 3200;

  /// 异步版（兼容旧调用 / 单测）。内部委托 [_runSync]。
  static Future<PreprocessResult> preprocess(String inputPath) async {
    final dir = await getTemporaryDirectory();
    return _runSync(inputPath, dir.path);
  }

  /// 同步执行全部密集预处理（不碰任何插件，可在 isolate 内运行）。
  ///
  /// [tempDir] 为临时目录路径（isolate 内无法调用 path_provider 插件，
  /// 故由主线程提前取好传入）。任何一步异常都回退原图，保证 OCR 不因预处理失败。
  static PreprocessResult _runSync(String inputPath, String tempDir) {
    try {
      final bytes = File(inputPath).readAsBytesSync();
      final decoded = decodeImage(bytes);
      if (decoded == null) {
        return PreprocessResult(
          processedPath: inputPath,
          sharpness: 1.0,
          blurry: false,
          width: 0,
          height: 0,
        );
      }

      var img = _applyOrientation(decoded);

      // 1. 高分辨率放大（宽表优先保证宽度）。
      img = _ensureResolution(img);

      // 2. 纠斜（扩大到 ±12°）。
      final angle = _estimateSkew(img);
      if (angle.abs() > 0.25) {
        img = copyRotate(img, angle: angle, interpolation: Interpolation.cubic);
      }

      // 3. 自适应对比度 + 轻微提亮（替代固定 contrast）。
      img = _adaptiveContrast(img);

      // 4. Unsharp Mask 锐化（对小数字特别有效）。
      img = _unsharpMask(img, amount: 1.4, radius: 1.0, threshold: 4);

      // 5. 绿底补偿：仅当图片确有大面积高饱和绿色（Excel 绿底高亮）才执行，
      //    普通截图/纸张翻拍直接跳过，省掉一遍全图像素循环。
      if (_hasGreenTint(img)) {
        img = _suppressGreenHighlight(img);
      }

      // 6. 清晰度评分。
      final sharpness = _estimateSharpness(img);

      // 7. 编码。
      final outBytes = encodeJpg(img, quality: 92);
      final outPath =
          '$tempDir/ocr_pre_${DateTime.now().microsecondsSinceEpoch}.jpg';
      File(outPath).writeAsBytesSync(outBytes);

      return PreprocessResult(
        processedPath: outPath,
        sharpness: sharpness,
        blurry: sharpness < _blurThreshold,
        width: img.width,
        height: img.height,
      );
    } catch (_) {
      return PreprocessResult(
        processedPath: inputPath,
        sharpness: 1.0,
        blurry: false,
        width: 0,
        height: 0,
      );
    }
  }

  /// 按 EXIF 朝向转正。
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

  /// 保证短边 ≥ [_minShortSide]，长边不超过 [_maxLongSide]。
  static Image _ensureResolution(Image img) {
    final shortSide = min(img.width, img.height);
    final longSide = max(img.width, img.height);
    if (shortSide >= _minShortSide && longSide <= _maxLongSide) return img;

    double scale = 1.0;
    if (shortSide < _minShortSide) {
      scale = _minShortSide / shortSide;
    }
    if (longSide * scale > _maxLongSide) {
      scale = _maxLongSide / longSide;
    }
    if ((scale - 1.0).abs() < 0.01) return img;

    final newW = (img.width * scale).round();
    final newH = (img.height * scale).round();
    return copyResize(img,
        width: newW, height: newH, interpolation: Interpolation.average);
  }

  /// 自适应对比度：按亮度百分位裁剪后拉伸到 0~255，再轻微提亮。
  static Image _adaptiveContrast(Image src) {
    final gray = grayscale(src);
    final hist = List<int>.filled(256, 0);
    final total = gray.width * gray.height;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        hist[gray.getPixel(x, y).luminance.round().clamp(0, 255)]++;
      }
    }

    // 1% / 99% 百分位
    int low = 0, high = 255;
    int acc = 0;
    final lowThresh = (total * 0.01).round();
    final highThresh = (total * 0.99).round();
    for (int i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= lowThresh && low == 0) low = i;
      if (acc >= highThresh) {
        high = i;
        break;
      }
    }
    if (high <= low) return src;

    final range = (high - low).toDouble();
    final out = Image.from(src);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        int stretch(num c) {
          final v = ((c - low) / range * 255.0).clamp(0.0, 255.0);
          // 轻微提亮
          return (v * 1.04).clamp(0.0, 255.0).round();
        }

        out.setPixelRgba(
          x,
          y,
          stretch(p.r),
          stretch(p.g),
          stretch(p.b),
          p.a.toInt(),
        );
      }
    }
    return out;
  }

  /// Unsharp Mask：amount 控制强度，radius 模糊半径，threshold 忽略小差异。
  static Image _unsharpMask(
    Image src, {
    double amount = 1.4,
    double radius = 1.0,
    int threshold = 4,
  }) {
    // 简单实现：原图 - 模糊图，再按 amount 叠加。
    final blurred = gaussianBlur(Image.from(src), radius: radius.round().clamp(1, 3));
    final out = Image.from(src);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final o = src.getPixel(x, y);
        final b = blurred.getPixel(x, y);
        int sharpen(num orig, num blur) {
          final diff = orig - blur;
          if (diff.abs() < threshold) return orig.round().clamp(0, 255);
          return (orig + amount * diff).round().clamp(0, 255);
        }

        out.setPixelRgba(
          x,
          y,
          sharpen(o.r, b.r),
          sharpen(o.g, b.g),
          sharpen(o.b, b.b),
          o.a.toInt(),
        );
      }
    }
    return out;
  }

  /// 采样预判是否存在大面积的 Excel 绿底高亮（绿色通道显著高于红蓝）。
  /// 每 24px 取一个样点，绿色占比 ≥5% 才认为需要绿底抑制。
  static bool _hasGreenTint(Image src) {
    final w = src.width, h = src.height;
    var total = 0, green = 0;
    for (int y = 0; y < h; y += 24) {
      for (int x = 0; x < w; x += 24) {
        final p = src.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        total++;
        if (g > r + 25 && g > b + 25 && g > 120) green++;
      }
    }
    return total > 0 && green / total >= 0.05;
  }

  /// 压低高饱和绿色（Excel 绿底高亮），让数字对比度回升。
  static Image _suppressGreenHighlight(Image src) {
    final out = Image.from(src);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        // 绿色通道显著高于红蓝 → 视为绿底
        if (g > r + 25 && g > b + 25 && g > 120) {
          // 向灰度靠拢，保留数字边缘
          final gray = (0.3 * r + 0.59 * g + 0.11 * b);
          const mix = 0.55; // 保留一点原色
          out.setPixelRgba(
            x,
            y,
            (r * (1 - mix) + gray * mix).round().clamp(0, 255),
            (g * (1 - mix) + gray * mix).round().clamp(0, 255),
            (b * (1 - mix) + gray * mix).round().clamp(0, 255),
            p.a.toInt(),
          );
        }
      }
    }
    return out;
  }

  /// 估计倾斜角（度）：±12° 粗扫 + 0.5° 细化。
  static double _estimateSkew(Image img) {
    final gray = grayscale(_resize(img, 400));
    double best = 0, bestVar = -1;

    for (double a = -12; a <= 12; a += 1.0) {
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

  static double _estimateSharpness(Image img) {
    final gray = grayscale(_resize(img, 360));
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
    final norm = sqrt(variance) / (255 * 2);
    return norm.clamp(0, 1);
  }

  static Image _resize(Image img, int width) {
    final height = (img.height * width / img.width).round();
    return copyResize(img,
        width: width, height: height, interpolation: Interpolation.average);
  }
}

/// 后台 isolate 入口：同步执行全部密集预处理，返回可序列化 Map。
///
/// 由 [ImagePreprocessor.preprocess] 的同款逻辑构成，但通过 `compute` 调度后
/// 运行在独立线程，主 UI 线程不被逐像素运算阻塞，根治导入图片卡顿。
Map<String, dynamic> preprocessInIsolate(Map<String, dynamic> args) {
  final inputPath = args['inputPath'] as String;
  final tempDir = args['tempDir'] as String;
  return ImagePreprocessor._runSync(inputPath, tempDir).toMap();
}

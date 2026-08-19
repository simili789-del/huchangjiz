import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/ocr_result.dart';
import '../../data/repositories/ocr_engine.dart';
import '../../core/util/monthly_report_parser.dart';

/// ROI 二次识别（仅增强姓名列）。
///
/// 设计目标：在不破坏月报结构的前提下，单独把最容易被误认的「中文姓名列」裁剪
/// 放大后再识别一次，按纵坐标映射回原行、只替换姓名文本。
///
/// 为什么只做姓名列、不做数字区：
/// 1. 数字区 ROI 用 average 插值放大 1.8× 会把小数字糊掉，反而更差；
/// 2. 数字/单价/表头本来就靠整图识别 + 解析器的抗倾斜对齐，ROI 重认只会把
///    「元/车」「早/晚/合计」这些解析器必需的结构信息丢掉，导致解析失败。
/// 3. 把所有姓名行拼成**一条竖条**、只调 1 次 ML Kit，识别次数从「每行 2 次
///    (姓名+数字) 串行」降到「主识别 1 次 + 姓名条 1 次」，根治导入后长时间等待。
///
/// 图像运算（解码/裁剪/缩放/编码）仍为密集像素操作，但只剩 1 张竖条，开销极小，
/// 直接在主线程完成即可；ML Kit 经插件必须在主线程调用。
class RoiOcr {
  /// 姓名列占图片宽度的最大比例。
  static const double nameColumnRatio = 0.12;

  /// 姓名条放大倍数（小字体更清晰）。
  static const double nameZoom = 1.8;

  /// 对整图 OCR 结果做「姓名列」定向增强。
  ///
  /// [fullLines] 整图识别结果（保留其全部结构/数字/表头）；[imagePath] 预处理后图片；
  /// [engine] 用于二次识别的离线引擎；[imageWidth]/[imageHeight] 预处理后尺寸。
  ///
  /// 返回**融合后**的行列表：原样保留 fullLines，仅把匹配到的姓名行文本替换为
  /// ROI 二次识别结果（更准的中文姓名）。任何异常都回退 fullLines，绝不越改越差。
  static Future<List<OcrLine>> refine({
    required List<OcrLine> fullLines,
    required String imagePath,
    required OcrEngine engine,
    required int imageWidth,
    required int imageHeight,
  }) async {
    if (fullLines.isEmpty || imageWidth <= 0) return fullLines;

    // 1. 找出靠左、2~4 个纯中文的姓名行。
    final nameRows = <OcrLine>[];
    for (final l in fullLines) {
      if (l.boundingBox == null) continue;
      if (l.boundingBox!.left < imageWidth * nameColumnRatio &&
          MonthlyReportParser.looksLikeNameLine(l.text)) {
        nameRows.add(l);
      }
    }
    if (nameRows.length < 2) return fullLines; // 太少没必要 ROI
    nameRows.sort((a, b) => a.boundingBox!.top.compareTo(b.boundingBox!.top));

    // 2. 姓名列上下边界 + 右边界。
    final nameRight = _estimateNameColumnRight(fullLines, imageWidth);
    final top = nameRows.first.boundingBox!.top - 6;
    final bottom = nameRows.last.boundingBox!.bottom + 6;

    // 3. 拼成一条姓名竖条（1 次解码 + 1 次裁剪 + 1 次缩放）。
    File? stripFile;
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return fullLines;

      const left = 0;
      final t = top.clamp(0, decoded.height - 1).round();
      final r = nameRight.clamp(left + 1, decoded.width).round();
      final b = bottom.clamp(t + 1, decoded.height).round();
      if (b - t < 8) return fullLines;

      var strip = img.copyCrop(decoded, x: left, y: t, width: r - left, height: b - t);
      strip = img.copyResize(
        strip,
        width: ((r - left) * nameZoom).round(),
        height: ((b - t) * nameZoom).round(),
        interpolation: img.Interpolation.cubic,
      );

      final dir = (await getTemporaryDirectory()).path;
      final stripPath =
          '$dir/roi_name_${DateTime.now().microsecondsSinceEpoch}.jpg';
      File(stripPath).writeAsBytesSync(img.encodeJpg(strip, quality: 95));
      stripFile = File(stripPath);

      // 4. 仅 1 次 ML Kit 识别。
      final recognized = await engine.recognize(stripPath);

      // 5. 按纵坐标把识别结果映射回各姓名行（竖条里 y 等比缩放）。
      final rowCenters =
          nameRows.map((l) => (l.boundingBox!.top + l.boundingBox!.bottom) / 2).toList();
      final newTexts = List<String?>.filled(nameRows.length, null);
      final tol = (b - t) / nameRows.length * 1.5;
      for (final rl in recognized) {
        final bb = rl.boundingBox;
        if (bb == null) continue;
        final stripCenter = (bb.top + bb.bottom) / 2;
        final fullCenter = t + stripCenter / nameZoom;
        int best = -1;
        double bestD = double.infinity;
        for (int i = 0; i < rowCenters.length; i++) {
          final d = (rowCenters[i] - fullCenter).abs();
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        if (best >= 0 && bestD <= tol) {
          final cn = rl.text.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
          if (cn.length >= 2 && cn.length <= 4) {
            if (newTexts[best] == null || cn.length > newTexts[best]!.length) {
              newTexts[best] = cn;
            }
          }
        }
      }

      // 6. 融合：原样保留 fullLines，只替换命中的姓名文本。
      final merged = fullLines.map((l) {
        final idx = nameRows.indexOf(l);
        if (idx >= 0 && newTexts[idx] != null) {
          return l.copyWith(text: newTexts[idx]!);
        }
        return l;
      }).toList();
      return merged;
    } catch (_) {
      return fullLines;
    } finally {
      try {
        await stripFile?.delete();
      } catch (_) {}
    }
  }

  /// 估算姓名列右边界：取靠左中文姓名行右边缘中位数，再与比例上限取 min。
  static double _estimateNameColumnRight(List<OcrLine> lines, int imageWidth) {
    final ratioCap = imageWidth * nameColumnRatio;
    final rights = <double>[];
    for (final l in lines) {
      final t = l.text.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
      if (t.length >= 2 && t.length <= 4 && l.boundingBox != null) {
        if (l.boundingBox!.left < imageWidth * 0.2) {
          rights.add(l.boundingBox!.right);
        }
      }
    }
    if (rights.isEmpty) return ratioCap;
    rights.sort();
    final median = rights[rights.length ~/ 2];
    return min(max(median + 8, imageWidth * 0.06), ratioCap * 1.4);
  }
}

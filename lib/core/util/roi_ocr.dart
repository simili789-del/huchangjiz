import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/ocr_result.dart';
import '../../data/repositories/ocr_engine.dart';

/// ROI 二次识别：对姓名列、数字区分别裁剪放大后再 OCR，提升密集表格准确率。
///
/// 流程：
/// 1. 用整图 OCR 结果粗定位姓名列右边界、表头行、合计列；
/// 2. 按逻辑行裁剪「数字区」→ 放大 1.6~2.0 倍 → 再 OCR（只关心数字）；
/// 3. 姓名列单独裁剪放大 → 再 OCR（只关心中文姓名）；
/// 4. 把二次识别结果按坐标合并回原行列表。
///
/// **卡顿修复**：步骤 2/3 的裁剪、放大、编码是密集像素运算，统一由
/// [buildRoisIsolate] + `compute` 调度到后台 isolate；主线程只保留
/// `engine.recognize`（ML Kit 经插件调用，必须在主 isolate）和坐标映射，
/// 导入图片时界面不再被 ROI 处理阻塞。
class RoiOcr {
  /// 姓名列占图片宽度的最大比例（相对化，替代写死 90px）。
  static const double nameColumnRatio = 0.12;

  /// 数字区二次识别放大倍数。
  static const double numberZoom = 1.8;

  /// 行高合并阈值相对平均行高的比例。
  static const double rowMergeRatio = 0.55;

  /// 对已有整图 OCR 结果做 ROI 增强。
  ///
  /// [fullLines] 整图识别结果；[imagePath] 预处理后的图片路径；
  /// [engine] 用于二次识别的引擎（通常仍是离线 ML Kit）；
  /// [imageWidth] 预处理后图片宽度。
  static Future<List<OcrLine>> refine({
    required List<OcrLine> fullLines,
    required String imagePath,
    required OcrEngine engine,
    required int imageWidth,
    required int imageHeight,
  }) async {
    if (fullLines.isEmpty || imageWidth <= 0) return fullLines;

    // 1. 估算姓名列右边界（相对宽度）。
    final nameRight = _estimateNameColumnRight(fullLines, imageWidth);

    // 2. 按垂直位置分组为逻辑行。
    final rows = _groupRows(fullLines, imageHeight);

    // 3. 构造每行的 ROI 参数（姓名区 + 数字区）。
    final roiArgs = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row.isEmpty) continue;
      final rowTop = row.map((l) => l.boundingBox?.top ?? 0).reduce(min);
      final rowBottom = row.map((l) => l.boundingBox?.bottom ?? 0).reduce(max);
      final pad = max(4.0, (rowBottom - rowTop) * 0.15);

      roiArgs.add(<String, dynamic>{
        'kind': 'name',
        'box': <double>[
          0,
          max(0, rowTop - pad),
          nameRight,
          min(imageHeight.toDouble(), rowBottom + pad),
        ],
        'zoom': 1.6,
      });
      roiArgs.add(<String, dynamic>{
        'kind': 'num',
        'box': <double>[
          nameRight,
          max(0, rowTop - pad),
          imageWidth.toDouble(),
          min(imageHeight.toDouble(), rowBottom + pad),
        ],
        'zoom': numberZoom,
      });
    }
    if (roiArgs.isEmpty) return fullLines;

    // 4. 后台 isolate 构建所有 ROI 临时图（裁切/放大/编码密集运算不阻塞 UI）。
    final bytes = await File(imagePath).readAsBytes();
    final dir = (await getTemporaryDirectory()).path;
    final built = await compute(
      buildRoisIsolate,
      <String, dynamic>{'bytes': bytes, 'dir': dir, 'rows': roiArgs},
    );

    // 5. 主 isolate 逐张 ML Kit 识别（插件必须在主 isolate）+ 坐标映射回原图。
    final refined = <OcrLine>[];
    for (final item in built) {
      final path = item['path'] as String;
      final kind = item['kind'] as String;
      final box = item['box'].cast<num>();
      final zoom = (item['zoom'] as num).toDouble();
      final boxLeft = box[0].toDouble();
      final boxTop = box[1].toDouble();
      final boxRight = box[2].toDouble();
      final boxBottom = box[3].toDouble();
      try {
        final lines = await engine.recognize(path);
        for (final l in lines) {
          if (kind == 'name') {
            final t = l.text.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
            if (t.length >= 2 && t.length <= 4) {
              refined.add(OcrLine(
                text: t,
                boundingBox:
                    Rect.fromLTRB(boxLeft, boxTop, boxRight, boxBottom),
              ));
            }
          } else {
            final local = l.boundingBox;
            if (local == null) {
              refined.add(OcrLine(
                text: l.text,
                boundingBox:
                    Rect.fromLTRB(boxLeft, boxTop, boxRight, boxBottom),
              ));
              continue;
            }
            // 二次识别图是放大后的，boundingBox 是放大图坐标，需缩回原图。
            final invZoom = 1.0 / zoom;
            refined.add(OcrLine(
              text: l.text,
              boundingBox: Rect.fromLTRB(
                boxLeft + local.left * invZoom,
                boxTop + local.top * invZoom,
                boxLeft + local.right * invZoom,
                boxTop + local.bottom * invZoom,
              ),
            ));
          }
        }
      } catch (_) {
        // 单张 ROI 失败不影响整体
      } finally {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }

    // 如果 ROI 几乎没产出，回退整图结果，避免越改越差。
    if (refined.length < fullLines.length * 0.3) {
      return fullLines;
    }
    return refined;
  }

  /// 估算姓名列右边界：取靠左的中文姓名行的右边缘中位数，再与比例上限取 min。
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

  static List<List<OcrLine>> _groupRows(List<OcrLine> lines, int imageHeight) {
    final sorted = [...lines]..sort((a, b) {
        final ta = a.boundingBox?.top ?? 0;
        final tb = b.boundingBox?.top ?? 0;
        return ta.compareTo(tb);
      });

    // 估算平均行高
    double avgH = 16;
    final heights = sorted
        .where((l) => l.boundingBox != null)
        .map((l) => l.boundingBox!.height)
        .where((h) => h > 4 && h < 80)
        .toList();
    if (heights.isNotEmpty) {
      heights.sort();
      avgH = heights[heights.length ~/ 2];
    }
    final mergeThresh = max(10.0, avgH * rowMergeRatio);

    final rows = <List<OcrLine>>[];
    for (final line in sorted) {
      if (line.text.trim().isEmpty) continue;
      final top = line.boundingBox?.top ?? 0;
      bool placed = false;
      for (final row in rows) {
        final rowTop = row.first.boundingBox?.top ?? 0;
        if ((top - rowTop).abs() < mergeThresh) {
          row.add(line);
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([line]);
    }
    return rows;
  }
}

/// 后台 isolate 入口：解码整图 → 逐行裁剪姓名区/数字区 → 放大 → 编码为临时文件。
///
/// 密集像素运算全部在此执行，返回每张 ROI 的临时图路径、类别与原始 box/zoom，
/// 供主线程做 ML Kit 识别与坐标映射。参数/返回值均为可序列化基本类型。
List<Map<String, dynamic>> buildRoisIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final dir = args['dir'] as String;
  final rows = (args['rows'] as List).cast<Map<String, dynamic>>();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const [];

  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final kind = r['kind'] as String;
    final box = (r['box'] as List).cast<num>();
    final zoom = (r['zoom'] as num).toDouble();

    final left = box[0].round().clamp(0, decoded.width - 1);
    final top = box[1].round().clamp(0, decoded.height - 1);
    final right = box[2].round().clamp(left + 1, decoded.width);
    final bottom = box[3].round().clamp(top + 1, decoded.height);
    final w = right - left;
    final h = bottom - top;
    if (w < 4 || h < 4) continue;

    var crop = img.copyCrop(decoded, x: left, y: top, width: w, height: h);
    if (zoom > 1.01) {
      crop = img.copyResize(
        crop,
        width: (w * zoom).round(),
        height: (h * zoom).round(),
        interpolation: img.Interpolation.average,
      );
    }

    final outPath =
        '$dir/roi_${kind}_${DateTime.now().microsecondsSinceEpoch}_${out.length}.jpg';
    File(outPath).writeAsBytesSync(img.encodeJpg(crop, quality: 92));

    out.add(<String, dynamic>{
      'path': outPath,
      'kind': kind,
      'box':
          <double>[left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble()],
      'zoom': zoom,
    });
  }
  return out;
}

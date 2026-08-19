import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/ocr_result.dart';
import '../../data/repositories/ocr_engine.dart';
import '../../core/util/monthly_report_parser.dart';

/// ROI 二次识别：以「姓名」为锚点，先定位每个人，再精读其名下区域。
///
/// 流程（对应需求「先识别姓名，再识别该姓名下的信息」）：
/// 1. 从整图 OCR 结果找出姓名行（靠左、2~4 个中文），作为锚点；
/// 2. 把所有姓名行拼成一条**竖条** → 1 次 ML Kit 识别，按纵坐标映射回各行，
///    只替换姓名文本（姓名认得更准）；
/// 3. 以每个人为一段，裁剪其**名下区域**（band：从上一个人名字底部到下一个人
///    名字顶部）→ 2 倍放大 → 各 1 次 ML Kit 识别，数字在小图上更清晰；
/// 4. 融合：band 结果带「元/车」单价行才算有效，此时用 band 行替换该段内
///    的整图行；否则回退保留整图行。表头（早/晚/合计/日期）始终来自整图。
///
/// 性能：识别次数 = 1（整图）+ 1（姓名条）+ N（每人一段）。整图负责表头网格，
/// 姓名条负责锚点，band 负责精读数字——每段都是小图，单次识别快。
///
/// 所有裁剪/缩放/编码在后台 isolate 一次性完成（[buildRefineBatchIsolate]），
/// 主线程只做 ML Kit 识别（插件必须在主线程）与坐标映射。
class RoiOcr {
  /// 姓名列占图片宽度的最大比例。
  static const double nameColumnRatio = 0.12;

  /// 姓名条放大倍数。
  static const double nameZoom = 1.8;

  /// band（人名下区域）放大倍数。
  static const double bandZoom = 2.0;

  /// 最后一个人的 band 高度上限（占图高比例），防超长误吸。
  static const double maxBandHeightRatio = 0.30;

  /// 对整图 OCR 结果做「姓名锚点 + 分块精读」增强。
  static Future<List<OcrLine>> refine({
    required List<OcrLine> fullLines,
    required String imagePath,
    required OcrEngine engine,
    required int imageWidth,
    required int imageHeight,
  }) async {
    if (fullLines.isEmpty || imageWidth <= 0) return fullLines;

    // 1. 定位姓名锚点。
    final nameRows = findNameRows(fullLines, imageWidth);
    if (nameRows.length < 2) return fullLines;
    nameRows.sort((a, b) => a.boundingBox!.top.compareTo(b.boundingBox!.top));

    // 2. 构造裁剪参数：姓名条 + 每人 band。
    final nameRight = _estimateNameColumnRight(fullLines, imageWidth);
    final stripTop = nameRows.first.boundingBox!.top - 6;
    final stripBottom = nameRows.last.boundingBox!.bottom + 6;
    final bandPlan = buildBandPlan(nameRows, imageHeight.toDouble());
    if (bandPlan.isEmpty) return fullLines;

    // 3. 后台 isolate 一次性构建所有裁剪图。
    final bytes = await File(imagePath).readAsBytes();
    final dir = (await getTemporaryDirectory()).path;
    final built = await compute(
      buildRefineBatchIsolate,
      <String, dynamic>{
        'bytes': bytes,
        'dir': dir,
        'nameRight': nameRight,
        'stripTop': stripTop,
        'stripBottom': stripBottom,
        'bandZoom': bandZoom,
        'nameZoom': nameZoom,
        'bands': bandPlan,
      },
    );

    // 4. 主线程逐张识别 + 坐标映射。
    final nameTexts = List<String?>.filled(nameRows.length, null);
    final bandLines = <int, List<OcrLine>>{};
    for (final item in built) {
      final path = item['path'] as String;
      final kind = item['kind'] as String;
      final top = (item['top'] as num).toDouble();
      final zoom = (item['zoom'] as num).toDouble();
      try {
        final lines = await engine.recognize(path);
        if (kind == 'name') {
          _mapNameLines(lines, nameRows, top, zoom, nameTexts);
        } else {
          final idx = item['rowIndex'] as int;
          final list = bandLines.putIfAbsent(idx, () => []);
          for (final l in lines) {
            final bb = l.boundingBox;
            if (bb == null) continue;
            list.add(OcrLine(
              text: l.text,
              boundingBox: Rect.fromLTRB(
                bb.left / zoom,
                top + bb.top / zoom,
                bb.right / zoom,
                top + bb.bottom / zoom,
              ),
            ));
          }
        }
      } catch (_) {
        // 单张失败不影响整体
      } finally {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }

    // 5. 融合（纯函数，可单测）。
    return mergeBandResults(
      fullLines: fullLines,
      nameRows: nameRows,
      nameTexts: nameTexts,
      bandLines: bandLines,
      imageHeight: imageHeight.toDouble(),
    );
  }

  // ------------------------------------------------------------------
  // 纯逻辑（@visibleForTesting 公开以便单测）
  // ------------------------------------------------------------------

  /// 找姓名锚点行：靠左、2~4 个纯中文、不含数字/单价词。
  @visibleForTesting
  static List<OcrLine> findNameRows(List<OcrLine> lines, int imageWidth) {
    final out = <OcrLine>[];
    for (final l in lines) {
      if (l.boundingBox == null) continue;
      if (l.boundingBox!.left < imageWidth * nameColumnRatio &&
          MonthlyReportParser.looksLikeNameLine(l.text)) {
        out.add(l);
      }
    }
    return out;
  }

  /// 生成每个姓名锚点的 band 计划：上边界=名字底部，下边界=下一个人名字顶部；
  /// 最后一个人下边界=min(图高, 名字底部+图高*[maxBandHeightRatio])。
  @visibleForTesting
  static List<Map<String, dynamic>> buildBandPlan(
    List<OcrLine> nameRows,
    double imageHeight,
  ) {
    final plan = <Map<String, dynamic>>[];
    for (int i = 0; i < nameRows.length; i++) {
      final nameBottom = nameRows[i].boundingBox?.bottom ?? 0;
      final nextTop = (i + 1 < nameRows.length)
          ? (nameRows[i + 1].boundingBox?.top ?? imageHeight)
          : imageHeight;
      var bottom = nextTop;
      if (i == nameRows.length - 1) {
        bottom = min(
          imageHeight,
          nameBottom + imageHeight * maxBandHeightRatio,
        );
      }
      final top = nameBottom;
      if (bottom - top < 8) continue;
      plan.add(<String, dynamic>{
        'rowIndex': i,
        'top': top,
        'bottom': bottom,
      });
    }
    return plan;
  }

  /// 融合规则（band 有效替换、无效回退）：
  /// - 姓名行：若姓名条识别出 2~4 字中文，替换文本；否则保留原文本。
  /// - band 内非姓名行：仅当该 band 识别结果含「元/车」单价行时，整体丢弃原行、
  ///   改用 band 行（含单价+数字，更准）；否则保留整图原行（兜底）。
  /// - band 范围外的行（表头 早/晚/合计/日期）：始终保留整图原行。
  @visibleForTesting
  static List<OcrLine> mergeBandResults({
    required List<OcrLine> fullLines,
    required List<OcrLine> nameRows,
    required List<String?> nameTexts,
    required Map<int, List<OcrLine>> bandLines,
    required double imageHeight,
  }) {
    // 姓名行在 fullLines 中的索引（身份同一性）。
    final nameIdx = <int>{};
    for (final r in nameRows) {
      final i = fullLines.indexOf(r);
      if (i >= 0) nameIdx.add(i);
    }

    // 1. 应用姓名文本。
    final corrected = <OcrLine>[];
    for (int i = 0; i < fullLines.length; i++) {
      final l = fullLines[i];
      final posInNames = nameRows.indexOf(l);
      final newText = posInNames >= 0 ? nameTexts[posInNames] : null;
      corrected.add(newText != null ? l.copyWith(text: newText) : l);
    }

    // 2. 哪些 band 有效（含 元/车 单价行）。
    final effective = <int>{};
    for (final e in bandLines.entries) {
      for (final l in e.value) {
        if (l.text.contains('元/车')) {
          effective.add(e.key);
          break;
        }
      }
    }

    // 3. 逐行决定保留/丢弃，band 内非姓名行且 band 有效 → 丢弃。
    final kept = <OcrLine>[];
    for (int i = 0; i < corrected.length; i++) {
      if (nameIdx.contains(i)) {
        kept.add(corrected[i]);
        continue;
      }
      final l = corrected[i];
      final bb = l.boundingBox;
      if (bb == null) {
        kept.add(l);
        continue;
      }
      final cy = bb.top + bb.height / 2;
      final bandIdx = _bandOf(cy, nameRows);
      if (bandIdx != null && effective.contains(bandIdx)) {
        continue; // 被 band 行替代
      }
      kept.add(l);
    }

    // 4. 加入有效 band 的行。
    for (final idx in effective) {
      kept.addAll(bandLines[idx]!);
    }

    kept.sort((a, b) =>
        (a.boundingBox?.top ?? 0).compareTo(b.boundingBox?.top ?? 0));
    return kept;
  }

  /// 该 y 属于哪个姓名 band（不含姓名行本身区域）。
  static int? _bandOf(double y, List<OcrLine> nameRows) {
    for (int i = 0; i < nameRows.length; i++) {
      final bottom = nameRows[i].boundingBox?.bottom ?? 0;
      final nextTop = (i + 1 < nameRows.length)
          ? (nameRows[i + 1].boundingBox?.top ?? double.infinity)
          : double.infinity;
      if (y >= bottom && y < nextTop) return i;
    }
    return null;
  }

  /// 姓名条识别结果 → 按纵坐标映射回各行，填充 [nameTexts]。
  static void _mapNameLines(
    List<OcrLine> recognized,
    List<OcrLine> nameRows,
    double stripTop,
    double zoom,
    List<String?> nameTexts,
  ) {
    final rowCenters = nameRows
        .map((l) => (l.boundingBox!.top + l.boundingBox!.bottom) / 2)
        .toList();
    final stripH = (nameRows.last.boundingBox!.bottom + 6) -
        (nameRows.first.boundingBox!.top - 6);
    final tol = stripH / nameRows.length * 1.5;
    for (final rl in recognized) {
      final bb = rl.boundingBox;
      if (bb == null) continue;
      final fullCenter = stripTop + (bb.top + bb.bottom) / 2 / zoom;
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
          if (nameTexts[best] == null || cn.length > nameTexts[best]!.length) {
            nameTexts[best] = cn;
          }
        }
      }
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

/// 后台 isolate 入口：解码整图一次，构建「姓名条 + 每人 band」的全部裁剪图。
List<Map<String, dynamic>> buildRefineBatchIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final dir = args['dir'] as String;
  final nameRight = (args['nameRight'] as num).toDouble();
  final stripTop = (args['stripTop'] as num).toDouble();
  final stripBottom = (args['stripBottom'] as num).toDouble();
  final bandZoom = (args['bandZoom'] as num).toDouble();
  final nameZoom = (args['nameZoom'] as num).toDouble();
  final bands = (args['bands'] as List).cast<Map<String, dynamic>>();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const [];

  final out = <Map<String, dynamic>>[];
  var n = 0;

  // 姓名条。
  final t0 = stripTop.clamp(0, decoded.height - 1).round();
  final b0 = stripBottom.clamp(t0 + 1, decoded.height).round();
  final r0 = nameRight.clamp(1, decoded.width).round();
  if (b0 - t0 >= 8 && r0 >= 4) {
    var strip = img.copyCrop(decoded, x: 0, y: t0, width: r0, height: b0 - t0);
    strip = img.copyResize(
      strip,
      width: (r0 * nameZoom).round(),
      height: ((b0 - t0) * nameZoom).round(),
      interpolation: img.Interpolation.cubic,
    );
    final p = '$dir/roi_name_${DateTime.now().microsecondsSinceEpoch}_$n.jpg';
    File(p).writeAsBytesSync(img.encodeJpg(strip, quality: 95));
    out.add(<String, dynamic>{'path': p, 'kind': 'name', 'top': t0.toDouble(), 'zoom': nameZoom});
    n++;
  }

  // 每人 band（整行宽）。
  for (final band in bands) {
    final t = (band['top'] as num).clamp(0, decoded.height - 1).round();
    final b = (band['bottom'] as num).clamp(t + 1, decoded.height).round();
    if (b - t < 8) continue;
    var crop = img.copyCrop(decoded, x: 0, y: t, width: decoded.width, height: b - t);
    crop = img.copyResize(
      crop,
      width: (decoded.width * bandZoom).round(),
      height: ((b - t) * bandZoom).round(),
      interpolation: img.Interpolation.cubic,
    );
    final p = '$dir/roi_band_${DateTime.now().microsecondsSinceEpoch}_$n.jpg';
    File(p).writeAsBytesSync(img.encodeJpg(crop, quality: 95));
    out.add(<String, dynamic>{
      'path': p,
      'kind': 'band',
      'rowIndex': band['rowIndex'] as int,
      'top': t.toDouble(),
      'zoom': bandZoom,
    });
    n++;
  }
  return out;
}

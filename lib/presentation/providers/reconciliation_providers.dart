import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/monthly_report_parser.dart';
import '../../core/util/name_matcher.dart';
import '../../data/repositories/ocr_repository.dart';
import '../../data/repositories/reconciliation_draft_repository.dart';
import '../../data/repositories/reconciliation_service.dart';
import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/reconciliation_result.dart';

/// 离线 OCR 引擎。M1 修复：使用 autoDispose，离开对账页时整棵对账 Provider 树
/// 被销毁、TextRecognizer 的 close() 被调用，释放占用的中文 OCR 模型（native
/// 资源，几十 MB）与相机/ML 相关资源——避免 App 启动即常驻内存、低配机吃紧。
final ocrRepositoryProvider = Provider.autoDispose<OcrRepository>((ref) {
  final repo = OcrRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final reconciliationDraftRepositoryProvider =
    Provider<ReconciliationDraftRepository>((ref) {
  return ReconciliationDraftRepository();
});

final reconciliationStateProvider = StateNotifierProvider.autoDispose<
    ReconciliationNotifier,
    ReconciliationState>((ref) {
  return ReconciliationNotifier(
    ref.watch(ocrRepositoryProvider),
    ref.watch(reconciliationDraftRepositoryProvider),
    RecordRepository(),
    SettingsRepository(),
  );
});

/// M2 对账页状态：选图 → OCR → 可编辑预览 → 存草稿 → 自动解析对账。
class ReconciliationState {
  final String? imagePath;
  final List<OcrLine> lines;
  final bool processing;
  final bool hasError;
  final String? errorMessage;
  final bool saved;

  /// 清晰度评分 0~1（来自 OCR 前图像分析）。
  final double sharpness;

  /// 是否疑似模糊（低于阈值，建议重拍）。
  final bool blurry;

  /// 是否正在执行对账解析。
  final bool reconciling;

  /// 对账结果（解析成功后填充）。
  final ReconciliationResult? result;

  const ReconciliationState({
    this.imagePath,
    this.lines = const [],
    this.processing = false,
    this.hasError = false,
    this.errorMessage,
    this.saved = false,
    this.sharpness = 1.0,
    this.blurry = false,
    this.reconciling = false,
    this.result,
  });

  ReconciliationState copyWith({
    String? imagePath,
    List<OcrLine>? lines,
    bool? processing,
    bool? hasError,
    String? errorMessage,
    bool? saved,
    double? sharpness,
    bool? blurry,
    bool? reconciling,
    ReconciliationResult? result,
    bool clearImage = false,
    bool clearResult = false,
  }) {
    return ReconciliationState(
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      lines: lines ?? this.lines,
      processing: processing ?? this.processing,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      saved: saved ?? this.saved,
      sharpness: sharpness ?? this.sharpness,
      blurry: blurry ?? this.blurry,
      reconciling: reconciling ?? this.reconciling,
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

class ReconciliationNotifier extends StateNotifier<ReconciliationState> {
  final OcrRepository _ocr;
  final ReconciliationDraftRepository _draft;
  final RecordRepository _recordRepo;
  final SettingsRepository _settingsRepo;

  ReconciliationNotifier(
    this._ocr,
    this._draft,
    this._recordRepo,
    this._settingsRepo,
  ) : super(const ReconciliationState());

  /// 选图后调用：记录图片路径并跑 OCR（含图像增强 + 姓名词典校正）。
  Future<void> recognize(String imagePath) async {
    state = state.copyWith(
      imagePath: imagePath,
      processing: true,
      hasError: false,
      errorMessage: null,
      saved: false,
      clearResult: true,
    );
    try {
      final rec = await _ocr.recognize(imagePath);

      // 预处理生成了新文件：删除原始临时图，避免缓存累积。
      if (imagePath != rec.processedImagePath) {
        try {
          await File(imagePath).delete();
        } catch (_) {
          // 忽略删除失败
        }
      }

      // 姓名词典校正：把 OCR 错字姓名纠回已知工人名，提升对账匹配率。
      final known = NameMatcher.collectKnownNames(_recordRepo, _settingsRepo);
      final correctedLines = rec.lines.map((l) {
        if (MonthlyReportParser.looksLikeNameLine(l.text)) {
          final fixed = NameMatcher.bestMatch(l.text, known);
          if (fixed != null && fixed != l.text) {
            return l.copyWith(text: fixed);
          }
        }
        return l;
      }).toList();

      state = state.copyWith(
        lines: correctedLines,
        imagePath: rec.processedImagePath,
        sharpness: rec.sharpness,
        blurry: rec.blurry,
        processing: false,
      );
    } catch (e, st) {
      debugPrint('OCR 失败: $e\n$st');
      state = state.copyWith(
        processing: false,
        hasError: true,
        errorMessage: e.toString(),
      );
    }
  }

  /// 用户在预览里改某一行文本。
  void updateLine(int index, String text) {
    if (index < 0 || index >= state.lines.length) return;
    final newLines = [...state.lines];
    newLines[index] = newLines[index].copyWith(text: text);
    state = state.copyWith(lines: newLines, saved: false, clearResult: true);
  }

  Future<void> saveDraft() async {
    // L4：草稿只保存识别文本行（imagePath 不持久化，见 ReconciliationDraftRepository）。
    await _draft.saveLatest(lines: state.lines);
    state = state.copyWith(saved: true);
  }

  /// M2：解析月报并与 App 内记录对账。
  Future<void> reconcile({int? year, int? month}) async {
    if (state.lines.isEmpty) return;
    state = state.copyWith(reconciling: true, hasError: false, errorMessage: null);
    try {
      final now = DateTime.now();
      final y = year ?? now.year;
      final m = month ?? now.month;

      final report = MonthlyReportParser.parse(state.lines, year: y, month: m);

      final start = DateTime(y, m, 1);
      final end = DateTime(y, m + 1, 0, 23, 59, 59);
      final records = _recordRepo.query(start: start, end: end);
      final unitPrices = _settingsRepo.getUnitPrices();

      final result = ReconciliationService.reconcile(report, records, unitPrices);
      state = state.copyWith(reconciling: false, result: result);
    } catch (e, st) {
      debugPrint('对账解析失败: $e\n$st');
      state = state.copyWith(
        reconciling: false,
        hasError: true,
        errorMessage: '对账解析失败：$e',
      );
    }
  }

  void reset() => state = const ReconciliationState();
}

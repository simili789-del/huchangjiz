import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/monthly_report_parser.dart';
import '../../core/util/name_matcher.dart';
import '../../data/repositories/ocr_engine.dart';
import '../../data/repositories/ocr_repository.dart';
import '../../data/repositories/reconciliation_draft_repository.dart';
import '../../data/repositories/reconciliation_service.dart';
import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/monthly_report.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/reconciliation_result.dart';
import 'qwen_providers.dart';

/// 离线 OCR 引擎。autoDispose：离开对账页释放 native 模型。
/// 云端引擎在「高精度」开关被打开时由 [ReconciliationNotifier.recognize]
/// 从 [qwenVlEngineOrNullProvider] 异步读取后通过 [OcrRepository.setCloudEngine] 注入。
final ocrRepositoryProvider = Provider.autoDispose<OcrRepository>((ref) {
  final repo = OcrRepository(
    mode: OcrEngineMode.offline,
    enableRoi: true,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// 高精度（云端）开关。默认关闭，用户可在对账页打开。
final ocrHighPrecisionProvider = StateProvider.autoDispose<bool>((ref) => false);

/// API Key 是否已配置（用于对账页右上角 Switch 的「未配置」提示）。
final qwenApiKeyConfiguredProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(secureSettingsRepositoryProvider);
  final key = await repo.getApiKey();
  return key != null && key.isNotEmpty;
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
    ref,
  );
});

/// M2 对账页状态。
class ReconciliationState {
  final String? imagePath;
  final List<OcrLine> lines;
  final bool processing;
  final bool hasError;
  final String? errorMessage;
  final bool saved;
  final double sharpness;
  final bool blurry;
  final bool reconciling;
  final ReconciliationResult? result;
  final int imageWidth;
  final int imageHeight;

  /// 云端 Qwen-VL 直出的结构化月报。非 null 时对账应跳过 [MonthlyReportParser]。
  final MonthlyReport? structuredReport;

  /// 最近一次云端调用错误（UI snackbar 提示用）。null = 无错误或未走云端。
  final String? cloudWarning;

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
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.structuredReport,
    this.cloudWarning,
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
    int? imageWidth,
    int? imageHeight,
    MonthlyReport? structuredReport,
    String? cloudWarning,
    bool clearImage = false,
    bool clearResult = false,
    bool clearStructured = false,
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
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      structuredReport:
          clearStructured ? null : (structuredReport ?? this.structuredReport),
      cloudWarning: cloudWarning ?? this.cloudWarning,
    );
  }
}

class ReconciliationNotifier extends StateNotifier<ReconciliationState> {
  final OcrRepository _ocr;
  final ReconciliationDraftRepository _draft;
  final RecordRepository _recordRepo;
  final SettingsRepository _settingsRepo;
  final Ref _ref;

  ReconciliationNotifier(
    this._ocr,
    this._draft,
    this._recordRepo,
    this._settingsRepo,
    this._ref,
  ) : super(const ReconciliationState());

  /// 选图后调用：记录图片路径并跑 OCR。
  Future<void> recognize(String imagePath) async {
    state = state.copyWith(
      imagePath: imagePath,
      processing: true,
      hasError: false,
      errorMessage: null,
      saved: false,
      clearResult: true,
      clearStructured: true,
    );
    try {
      // 根据高精度开关切换引擎
      final highPrecision = _ref.read(ocrHighPrecisionProvider);
      _ocr.mode =
          highPrecision ? OcrEngineMode.cloud : OcrEngineMode.offline;

      // 云端模式：从 secure storage 异步加载 Qwen 引擎并注入到 OcrRepository
      if (highPrecision) {
        final engine = await _ref.read(qwenVlEngineOrNullProvider.future);
        if (engine == null) {
          // 未配 key：自动降级 offline + 提示
          _ocr.setCloudEngine(null);
          _ocr.mode = OcrEngineMode.offline;
          state = state.copyWith(
            cloudWarning: '未配置阿里云 API Key，已自动降级离线识别',
          );
        } else {
          _ocr.setCloudEngine(engine);
        }
      } else {
        _ocr.setCloudEngine(null);
      }

      final rec = await _ocr.recognize(imagePath);

      if (imagePath != rec.processedImagePath) {
        try {
          await File(imagePath).delete();
        } catch (_) {}
      }

      // 行级路径：姓名词典校正（云端结构化路径无需此步）
      var correctedLines = rec.lines;
      if (rec.structuredReport == null) {
        final known = NameMatcher.collectKnownNames(_recordRepo, _settingsRepo);
        correctedLines = rec.lines.map((l) {
          if (MonthlyReportParser.looksLikeNameLine(l.text)) {
            final fixed = NameMatcher.bestMatch(l.text, known);
            if (fixed != null && fixed != l.text) {
              return l.copyWith(text: fixed);
            }
          }
          return l;
        }).toList();
      }

      // 合并 cloud warning
      String? mergedWarning = state.cloudWarning ?? _ocr.lastCloudError;

      state = state.copyWith(
        lines: correctedLines,
        imagePath: rec.processedImagePath,
        sharpness: rec.sharpness,
        blurry: rec.blurry,
        processing: false,
        imageWidth: rec.imageWidth,
        imageHeight: rec.imageHeight,
        structuredReport: rec.structuredReport,
        cloudWarning: mergedWarning,
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

  void updateLine(int index, String text) {
    if (index < 0 || index >= state.lines.length) return;
    final newLines = [...state.lines];
    newLines[index] = newLines[index].copyWith(text: text);
    state = state.copyWith(lines: newLines, saved: false, clearResult: true);
  }

  Future<void> saveDraft() async {
    await _draft.saveLatest(lines: state.lines);
    state = state.copyWith(saved: true);
  }

  Future<void> reconcile({int? year, int? month}) async {
    if (state.lines.isEmpty && state.structuredReport == null) return;
    state = state.copyWith(reconciling: true, hasError: false, errorMessage: null);
    try {
      final now = DateTime.now();
      final y = year ?? now.year;
      final m = month ?? now.month;

      final MonthlyReport report;
      if (state.structuredReport != null) {
        // 云端直出：直接用 Qwen-VL 返回的结构化月报，跳过行级解析器（accuracy 最高）
        report = state.structuredReport!;
        // 如果用户没指定年月，用结构化报告自带的
        if (year == null && month == null) {
          // 已在 report.year/month；不影响后续 start/end
        }
      } else {
        // 行级路径：老逻辑不变
        report = MonthlyReportParser.parse(
          state.lines,
          year: y,
          month: m,
          imageWidth: state.imageWidth > 0 ? state.imageWidth : null,
        );
      }

      final start = DateTime(y, m, 1);
      final end = DateTime(y, m + 1, 0, 23, 59, 59);
      final records = _recordRepo.query(start: start, end: end);
      final unitPrices = _settingsRepo.getUnitPrices();

      final result =
          ReconciliationService.reconcile(report, records, unitPrices);
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

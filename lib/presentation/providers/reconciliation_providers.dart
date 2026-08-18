import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/ocr_repository.dart';
import '../../data/repositories/reconciliation_draft_repository.dart';
import '../../domain/entities/ocr_result.dart';

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
  );
});

/// M1 对账页状态：选图 → OCR → 可编辑预览 → 存草稿。
class ReconciliationState {
  final String? imagePath;
  final List<OcrLine> lines;
  final bool processing;
  final bool hasError;
  final String? errorMessage;
  final bool saved;

  const ReconciliationState({
    this.imagePath,
    this.lines = const [],
    this.processing = false,
    this.hasError = false,
    this.errorMessage,
    this.saved = false,
  });

  ReconciliationState copyWith({
    String? imagePath,
    List<OcrLine>? lines,
    bool? processing,
    bool? hasError,
    String? errorMessage,
    bool? saved,
    bool clearImage = false,
  }) {
    return ReconciliationState(
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      lines: lines ?? this.lines,
      processing: processing ?? this.processing,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      saved: saved ?? this.saved,
    );
  }
}

class ReconciliationNotifier extends StateNotifier<ReconciliationState> {
  final OcrRepository _ocr;
  final ReconciliationDraftRepository _draft;

  ReconciliationNotifier(this._ocr, this._draft)
      : super(const ReconciliationState());

  /// 选图后调用：记录图片路径并跑 OCR。
  Future<void> recognize(String imagePath) async {
    state = state.copyWith(
      imagePath: imagePath,
      processing: true,
      hasError: false,
      errorMessage: null,
      saved: false,
    );
    try {
      final lines = await _ocr.recognize(imagePath);
      state = state.copyWith(lines: lines, processing: false);
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
    state = state.copyWith(lines: newLines, saved: false);
  }

  Future<void> saveDraft() async {
    // L4：草稿只保存识别文本行（imagePath 不持久化，见 ReconciliationDraftRepository）。
    await _draft.saveLatest(lines: state.lines);
    state = state.copyWith(saved: true);
  }

  void reset() => state = const ReconciliationState();
}

import 'package:hive/hive.dart';

import '../../domain/entities/ocr_result.dart';

/// 对账识别草稿（临时存档，供 M2 解析对账读取）。
///
/// 用「非类型化 Hive 盒子」存 JSON，避免注册 Adapter、保持低侵入。
/// M1 负责写，M2 负责读并解析成结构化表格。
class ReconciliationDraftRepository {
  static const String boxName = 'reconciliation_drafts';
  static const String _key = 'latest';

  Box get _box => Hive.box(boxName);

  Future<void> saveLatest({
    required List<OcrLine> lines,
  }) async {
    // L4 修复：不持久化 imagePath。image_picker 返回的是缓存目录临时文件，
    // App 重启后即失效，存下也无法恢复显示；且 M2 解析对账只依赖识别出的
    // 文本行（lines），与图片无关。故草稿仅保存行数据 + 时间戳。
    await _box.put(_key, {
      'createdAt': DateTime.now().toIso8601String(),
      'lines': lines.map((l) => l.toJson()).toList(),
    });
  }

  Map<dynamic, dynamic>? loadLatest() => _box.get(_key);
}

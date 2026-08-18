import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';

/// 姓名词典校正：用 App 内「已有工人名」对 OCR 错字姓名做模糊匹配纠回。
///
/// 会计月报里的姓名一旦被 OCR 认错一个字（如「刘松样」），后续按姓名对账就
/// 匹配不上 App 里的真实记录。App 已经积累了手录的工人名 + 设置里的固定名单，
/// 拿它们做字典，把 OCR 姓名纠回正确写法，对账成功率直接提升。
class NameMatcher {
  /// 汇总已知工人名：手录记录去重 + 设置里的固定人员名单。
  static List<String> collectKnownNames(
    RecordRepository recordRepo,
    SettingsRepository settingsRepo,
  ) {
    final set = <String>{};
    for (final r in recordRepo.all) {
      if (r.workerName.isNotEmpty) set.add(r.workerName);
    }
    for (final w in settingsRepo.getFixedWorkers()) {
      if (w.isNotEmpty) set.add(w);
    }
    return set.toList();
  }

  /// 把 OCR 识别出的姓名纠回已知名。
  ///
  /// 命中优先级：精确 → 包含 → 编辑距离 ≤1。都未命中返回 null（不改，交给用户手改）。
  /// [ocrName] 可为 OCR 原文本（内部会去掉非中文再比对）。
  static String? bestMatch(String ocrName, List<String> known) {
    final norm = _normalize(ocrName);
    if (norm.isEmpty) return null;

    // 1. 精确（忽略非中文字符，如「刘松祥.」）。
    for (final k in known) {
      if (_normalize(k) == norm) return k;
    }
    // 2. 包含（OCR 多/漏了字，或字典名是子集/超集）。
    for (final k in known) {
      final nk = _normalize(k);
      if (nk.contains(norm) || norm.contains(nk)) return k;
    }
    // 3. 编辑距离 ≤1（错/漏/多一个字，如「刘松样」「刘松样祥」）。
    String? best;
    var bestD = 2;
    for (final k in known) {
      final d = _editDistance(norm, _normalize(k));
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return bestD <= 1 ? best : null;
  }

  /// 去掉非中文字符，仅保留姓名本体用于比对。
  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');

  /// 中文短串编辑距离（Levenshtein）。姓名 2-4 字，开销极小。
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (int i = 1; i <= m; i++) {
      cur[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = _min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[n];
  }

  static int _min3(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}

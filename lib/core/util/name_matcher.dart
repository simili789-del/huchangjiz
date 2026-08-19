import '../../data/repositories/record_repository.dart';
import '../../data/repositories/settings_repository.dart';

/// 姓名词典校正：用 App 内「已有工人名」对 OCR 错字姓名做模糊匹配纠回。
///
/// 增强点：
/// - 编辑距离：2~3 字 ≤1，4 字 ≤2
/// - 形近字表（样↔祥、平↔坪…）归一后再比
class NameMatcher {
  /// 常见 OCR 形近/易混中文字符映射（归一到规范写法）。
  static const Map<String, String> _similarCharMap = {
    '样': '祥',
    '坪': '平',
    '苹': '平',
    '淞': '松',
    '扬': '杨',
    '浏': '刘',
    '章': '张',
    '吾': '吴',
    '萧': '肖',
    '阎': '闫',
    // 可按实际错例继续扩充
  };

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
  /// 命中优先级：精确 → 形近归一精确 → 包含 → 编辑距离（自适应阈值）→ null。
  static String? bestMatch(String ocrName, List<String> known) {
    final norm = _normalize(ocrName);
    if (norm.isEmpty) return null;

    final normSimilar = _normalizeSimilar(norm);

    // 1. 精确。
    for (final k in known) {
      if (_normalize(k) == norm) return k;
    }

    // 2. 形近归一后精确。
    for (final k in known) {
      if (_normalizeSimilar(_normalize(k)) == normSimilar) return k;
    }

    // 3. 包含。
    for (final k in known) {
      final nk = _normalize(k);
      if (nk.isEmpty) continue;
      if (nk.contains(norm) || norm.contains(nk)) return k;
      final nks = _normalizeSimilar(nk);
      if (nks.contains(normSimilar) || normSimilar.contains(nks)) return k;
    }

    // 4. 编辑距离（2~3 字 ≤1，≥4 字 ≤2）。
    final maxDist = norm.length >= 4 ? 2 : 1;
    String? best;
    var bestD = maxDist + 1;
    for (final k in known) {
      final nk = _normalize(k);
      if (nk.isEmpty) continue;
      var d = _editDistance(norm, nk);
      final d2 = _editDistance(normSimilar, _normalizeSimilar(nk));
      if (d2 < d) d = d2;
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return bestD <= maxDist ? best : null;
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');

  static String _normalizeSimilar(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      buf.write(_similarCharMap[ch] ?? ch);
    }
    return buf.toString();
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    if ((m - n).abs() > 2) return (m - n).abs();
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

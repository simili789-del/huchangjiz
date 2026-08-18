import '../../domain/entities/ocr_result.dart';

/// OCR 后处理：纠正数字 / 金额字段中常见的「形近字符」误识。
///
/// ML Kit 中文识别在数字与字母交界处，常把数字误识为形似的字母或符号，
/// 例如：`0↔O` `1↔l/I` `2↔Z` `5↔S` `6↔G` `8↔B`。这些误识集中在金额、吨数、
/// 车号等纯数字字段，也最直接影响对账准确性。
///
/// 设计原则（避免误改）：
/// - 只作用于「数字占多数」的连续片段，纯中文 / 英文混排的句子原样保留；
/// - 全角数字与全角小数点统一归一到半角，方便后续解析；
/// - 不引入任何业务词典，避免把正确的中文（如「盹」「乍」）错改成别的字。
const Map<String, String> _lookalikeToDigit = {
  // 半角形近字母 → 数字
  'O': '0', 'o': '0',
  'I': '1', 'l': '1', '|': '1',
  'Z': '2', 'z': '2',
  'S': '5', 's': '5',
  'B': '8',
  'G': '6', 'g': '6',
  // 全角数字 → 半角
  '０': '0', '１': '1', '２': '2', '３': '3', '４': '4',
  '５': '5', '６': '6', '７': '7', '８': '8', '９': '9',
  // 全角小数点 → 半角
  '．': '.',
};

/// 匹配由「半角/全角数字 + 形近字母 + 小数点/千分位逗号」组成的连续片段。
final RegExp _numericSegment = RegExp(r'[0-9０-９OoIlZzSsBbgG|.,．]+');

/// 纠正单行 OCR 文本中的数字字段形近误识。
String correctOcrText(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(_numericSegment, (m) {
    final seg = m.group(0)!;
    final digitCount =
        seg.replaceAll(RegExp(r'[^0-9０-９]'), '').length;
    final lookalikeCount =
        seg.replaceAll(RegExp(r'[0-9０-９.,．]'), '').length;
    // 仅当数字（含全角）占多数时才纠正，避免误伤中文 / 英文混排内容。
    if (digitCount == 0 || lookalikeCount > digitCount) return seg;
    return seg
        .split('')
        .map((c) => _lookalikeToDigit[c] ?? c)
        .join('');
  });
}

/// 批量纠正 OCR 行列表（保持原有坐标框不变）。
List<OcrLine> correctOcrLines(List<OcrLine> lines) {
  return lines
      .map((l) => OcrLine(text: correctOcrText(l.text), boundingBox: l.boundingBox))
      .toList();
}

import 'dart:ui' show Rect;

/// OCR 识别出的一行文本（含位置框，供 M2 表格解析按坐标归位使用）。
class OcrLine {
  final String text;
  final Rect? boundingBox;

  const OcrLine({required this.text, this.boundingBox});

  OcrLine copyWith({String? text, Rect? boundingBox}) => OcrLine(
        text: text ?? this.text,
        boundingBox: boundingBox ?? this.boundingBox,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'bbox': boundingBox == null
            ? null
            : {
                'left': boundingBox!.left,
                'top': boundingBox!.top,
                'right': boundingBox!.right,
                'bottom': boundingBox!.bottom,
              },
      };

  factory OcrLine.fromJson(Map<dynamic, dynamic> json) => OcrLine(
        text: (json['text'] as String?) ?? '',
        boundingBox: json['bbox'] == null
            ? null
            : Rect.fromLTRB(
                (json['bbox']['left'] as num).toDouble(),
                (json['bbox']['top'] as num).toDouble(),
                (json['bbox']['right'] as num).toDouble(),
                (json['bbox']['bottom'] as num).toDouble(),
              ),
      );
}

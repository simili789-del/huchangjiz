import 'dart:ui' show Rect;

/// OCR 识别出的一行文本（含位置框，供表格解析按坐标归位使用）。
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

/// OCR 识别结果：增强后的图片路径 + 识别文本行 + 清晰度信息 + 尺寸。
class OcrRecognition {
  /// 识别用的（已做 OCR 前增强的）图片路径，同时用于界面展示。
  final String processedImagePath;

  /// 识别出的文本行（已过数字纠错，可能经过 ROI 二次识别）。
  final List<OcrLine> lines;

  /// 清晰度评分 0~1，越大越清晰。
  final double sharpness;

  /// 是否疑似模糊（低于阈值，建议重拍）。
  final bool blurry;

  /// 预处理后图片宽度（供解析层相对坐标）。
  final int imageWidth;

  /// 预处理后图片高度。
  final int imageHeight;

  OcrRecognition({
    required this.processedImagePath,
    required this.lines,
    required this.sharpness,
    required this.blurry,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });
}

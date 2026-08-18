# ============================================================
# R8 / ProGuard 规则（release 构建）
# ============================================================
#
# 背景：google_mlkit_text_recognition 从 0.13+ 起将各语言识别模型拆分为独立包
# （chinese / japanese / korean / devanagari / latin）。其主包 Java 层
# TextRecognizer.initialize() 会静态引用上述各语言的 XxxTextRecognizerOptions 类，
# 但本应用仅使用中文（ocr_repository.dart: TextRecognitionScript.chinese）。
#
# 后果：未引入的语言包类不在依赖树中，release 模式下 R8 报
#   "Missing class com.google.mlkit.vision.text.japanese/.../korean/.../devanagari/..."
# 导致 minifyReleaseWithR8 失败。
#
# 处理：
#   1. 中文类由 google_mlkit_text_recognition_chinese 包真实提供（已在 pubspec 引入），无需忽略。
#   2. 其余未使用的语言类用 -dontwarn 抑制 R8 检查。
#      Java 链接是惰性的，运行时只走 chinese 分支，不会加载其余语言类，故安全。

-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# 通用兜底：ML Kit 内部反射/原生符号，避免误删导致运行时崩溃。
-keep class com.google.mlkit.** { *; }

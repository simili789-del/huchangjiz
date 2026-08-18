import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 分享临时文件前缀：用于识别并清理历史残留，避免立即删除正在分享的文件。
const _shareFilePrefix = 'yard_export_';

/// 把文本内容写成临时文件，并调用系统分享面板交给用户保存/发送。
///
/// 临时目录位于 App 缓存区，[share_plus] 自带的 FileProvider 已覆盖该路径，
/// 无需额外声明 Android 权限或 manifest 配置。
///
/// 使用 share_plus 7.x 静态 API：[Share.shareXFiles]。
Future<void> shareTextFile(String content, String filename) async {
  final dir = await getTemporaryDirectory();
  final safeName = filename.split(RegExp(r'[/\\]')).last;
  final file = File('${dir.path}/$_shareFilePrefix$safeName');
  await file.writeAsBytes(utf8.encode(content), flush: true);
  await Share.shareXFiles(
    [XFile(file.path)],
    text: '货场记账导出',
  );
}

/// 清理历史分享产生的临时文件（在 App 启动时调用一次）。
///
/// 不在分享结束后立即删除，以免系统分享目标尚未读取文件就被删掉；
/// 改为下次启动时统一清理上次及更早的残留，避免临时文件无限累积（M5）。
Future<void> cleanupStaleShareFiles() async {
  try {
    final dir = await getTemporaryDirectory();
    final entries = dir.listSync();
    for (final e in entries) {
      if (e is File && e.path.split('/').last.startsWith(_shareFilePrefix)) {
        try {
          await e.delete();
        } catch (_) {
          // 个别文件删除失败可忽略
        }
      }
    }
  } catch (_) {
    // 临时目录不可用时忽略
  }
}

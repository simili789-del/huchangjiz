import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把文本内容写成临时文件，并调用系统分享面板交给用户保存/发送。
///
/// 临时目录位于 App 缓存区，[share_plus] 自带的 FileProvider 已覆盖该路径，
/// 无需额外声明 Android 权限或 manifest 配置。
///
/// 使用 share_plus 7.x 静态 API：[Share.shareXFiles]。
Future<void> shareTextFile(String content, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(utf8.encode(content), flush: true);
  await Share.shareXFiles(
    [XFile(file.path)],
    text: '货场记账导出',
  );
}

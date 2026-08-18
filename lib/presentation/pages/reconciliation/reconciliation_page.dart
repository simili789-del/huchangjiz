import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/reconciliation_providers.dart';

/// M1 月报对账页：拍照/选图 → 离线 OCR → 可手动改数的识别预览 → 存草稿。
///
/// 注意：自动「解析 + 与 App 数据对账」是 M2 的事；本页只负责把图片
/// 变成可编辑的文本行，并暂存为草稿，供 M2 读取。
class ReconciliationPage extends ConsumerStatefulWidget {
  const ReconciliationPage({super.key});

  @override
  ConsumerState<ReconciliationPage> createState() =>
      _ReconciliationPageState();
}

class _ReconciliationPageState extends ConsumerState<ReconciliationPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pick(ImageSource source) async {
    final prev = ref.read(reconciliationStateProvider).imagePath;
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file != null && context.mounted) {
      await ref.read(reconciliationStateProvider.notifier).recognize(file.path);
      // L3：重新拍摄/选择后，上一轮的临时图片文件已不再使用，删除避免累积。
      _deleteTemp(prev);
    }
  }

  /// 删除 image_picker 产生的缓存临时文件（若存在）。App 重启后也可能残留，
  /// 离开对账页时在 dispose 中一并清理。
  void _deleteTemp(String? p) {
    if (p == null || p.isEmpty) return;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 忽略删除失败（文件可能已被系统清理）
    }
  }

  @override
  void dispose() {
    // L3：离开对账页时清理当前临时图片文件。
    _deleteTemp(ref.read(reconciliationStateProvider).imagePath);
    super.dispose();
  }

  Future<void> _showPickSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationStateProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('月报对账'),
        actions: [
          if (state.imagePath != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新拍摄 / 选择',
              onPressed: _showPickSheet,
            ),
        ],
      ),
      body: _Body(state: state),
      floatingActionButton: state.imagePath == null
          ? FloatingActionButton.extended(
              onPressed: _showPickSheet,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('拍照 / 选图'),
            )
          : null,
    );
  }
}

class _Body extends ConsumerWidget {
  final ReconciliationState state;
  const _Body({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.imagePath == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '点击下方按钮，拍下或选择会计发的「月度作业量汇总表」，开始智能对账。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
    }
    if (state.processing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('识别中…'),
          ],
        ),
      );
    }
    if (state.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '识别失败：${state.errorMessage ?? ''}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        if (state.imagePath != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(state.imagePath!),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '识别结果（OCR 可能有误，请点格子改数）：',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: state.lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _EditableLine(
              initialText: state.lines[i].text,
              onChanged: (v) =>
                  ref.read(reconciliationStateProvider.notifier).updateLine(i, v),
            ),
          ),
        ),
        _ActionBar(state: state),
      ],
    );
  }
}

/// 单行可编辑文本。自管 [TextEditingController]，避免父级重建导致光标跳尾。
class _EditableLine extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;
  const _EditableLine({required this.initialText, required this.onChanged});

  @override
  State<_EditableLine> createState() => _EditableLineState();
}

class _EditableLineState extends State<_EditableLine> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          style: const TextStyle(fontSize: 15),
        ),
      );
}

class _ActionBar extends ConsumerWidget {
  final ReconciliationState state;
  const _ActionBar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(state.saved ? '已保存草稿' : '保存识别草稿'),
                onPressed: state.saved
                    ? null
                    : () async {
                        await ref
                            .read(reconciliationStateProvider.notifier)
                            .saveDraft();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('已保存识别草稿，自动解析对账（M2）即将上线'),
                          ));
                        }
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('开始对账'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('自动解析对账（M2）即将上线，请先保存草稿'),
                  ));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

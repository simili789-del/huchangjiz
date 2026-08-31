import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/entities/reconciliation_result.dart';
import '../../providers/reconciliation_providers.dart';

/// M2 月报对账页：拍照/选图 → 离线 OCR → 可手动改数的识别预览 → 自动解析对账。
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
    final keyConfigured =
        ref.watch(qwenApiKeyConfiguredProvider).valueOrNull ?? false;

    // 云端降级/未配 key 提示（snackbar）
    ref.listen(reconciliationStateProvider, (prev, next) {
      final w = next.cloudWarning;
      if (w != null && w != prev?.cloudWarning && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(w),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('月报对账'),
        actions: [
          // 高精度（云端）开关 + Key 状态点
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '高精度',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Tooltip(
                message: keyConfigured ? '阿里云 Qwen-VL 已就绪' : '未配置 API Key（去设置）',
                child: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: keyConfigured ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              Switch(
                value: ref.watch(ocrHighPrecisionProvider),
                onChanged: (v) {
                  if (v && !keyConfigured) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请先到「设置 → 云端识别」配置阿里云 API Key'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                  ref.read(ocrHighPrecisionProvider.notifier).state = v;
                },
              ),
            ],
          ),
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
            '拍下或选择会计发的「月度作业量汇总表」，开始智能对账。\n\n'
            '📸 拍摄小贴士：\n'
            '· 横屏、完整表头、表格尽量铺满屏幕\n'
            '· 手机与纸面/屏幕平行，避免透视变形\n'
            '· 光线充足、无反光；模糊时请重拍\n'
            '· 关键月报可打开右上角「高精度」开关',
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
        if (state.blurry)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '照片有点模糊，识别可能不准，建议重拍一张更清晰的。',
                    style: TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        if (state.structuredReport != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Qwen-VL 云端直出 ${state.structuredReport!.entries.length} 个员工 · '
                    '${state.structuredReport!.totalCars} 车 · 已跳过行级识别器，准确率最高',
                    style: const TextStyle(fontSize: 13, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '识别结果（OCR 可能有误，请点格子改数）：',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // 对账结果（M2）
        if (state.result != null) ...[
          _ReconciliationSummaryCard(summary: state.result!.summary),
          Expanded(
            child: _ReconciliationResultList(items: state.result!.items),
          ),
        ] else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: state.lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _EditableLine(
                initialText: state.lines[i].text,
                onChanged: (v) => ref
                    .read(reconciliationStateProvider.notifier)
                    .updateLine(i, v),
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
                            content: Text('已保存识别草稿'),
                          ));
                        }
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: state.reconciling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(state.reconciling ? '对账中…' : '开始对账'),
                onPressed: state.reconciling
                    ? null
                    : () async {
                        await ref
                            .read(reconciliationStateProvider.notifier)
                            .reconcile();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 对账汇总卡片。
class _ReconciliationSummaryCard extends StatelessWidget {
  final ReconciliationSummary summary;
  const _ReconciliationSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '对账汇总：共 ${summary.total} 条',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryChip(label: '一致', value: summary.matched, color: Colors.green),
                _SummaryChip(label: '月报独有', value: summary.reportOnly, color: Colors.orange),
                _SummaryChip(label: 'App 独有', value: summary.appOnly, color: Colors.blue),
                _SummaryChip(label: '数量不符', value: summary.mismatch, color: Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

/// 对账差异列表（默认只看差异，可切换全部）。
class _ReconciliationResultList extends StatefulWidget {
  final List<ReconciliationItem> items;
  const _ReconciliationResultList({required this.items});

  @override
  State<_ReconciliationResultList> createState() => _ReconciliationResultListState();
}

class _ReconciliationResultListState extends State<_ReconciliationResultList> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final displayItems = _showAll
        ? widget.items
        : widget.items.where((i) => i.type != DifferenceType.matched).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                _showAll ? '全部结果' : '只看差异',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                icon: Icon(_showAll ? Icons.filter_list_off : Icons.filter_list),
                label: Text(_showAll ? '只看差异' : '显示全部'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = displayItems[i];
              return ListTile(
                dense: true,
                leading: _DifferenceBadge(type: item.type),
                title: Text('${item.workerName} · ${item.day}日${item.shift}班'),
                subtitle: Text(
                  '${item.jobType ?? '未知类型'} · ${item.price.toStringAsFixed(1)}元/车',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('月报 ${item.reportCount}', style: const TextStyle(fontSize: 13)),
                    Text('App ${item.appCount}', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DifferenceBadge extends StatelessWidget {
  final DifferenceType type;
  const _DifferenceBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      DifferenceType.matched => Colors.green,
      DifferenceType.reportOnly => Colors.orange,
      DifferenceType.appOnly => Colors.blue,
      DifferenceType.mismatch => Colors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/job_types.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/share_file.dart';
import '../../../data/serialization/record_serialization.dart';
import '../../../data/repositories/qwen_vl_ocr_engine.dart';
import '../../../domain/entities/salary_settings.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/qwen_providers.dart';
import '../../providers/reconciliation_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/selected_date_record_provider.dart';
import '../../widgets/section_header.dart';
import '../../widgets/yard_app_bar.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const YardAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          _ProfileSection(),
          _JobTypePriceSection(),
          _SalarySection(),
          _AppearanceSection(),
          _TargetSection(),
          _OcrSection(),
          _BackupSection(),
        ],
      ),
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection();

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  final _workerCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();
  final _yardCtrl = TextEditingController();
  bool _synced = false;

  @override
  void dispose() {
    _workerCtrl.dispose();
    _vehicleCtrl.dispose();
    _yardCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    // 仅首次把已保存值填入输入框；之后由用户输入驱动，避免每次重建覆盖光标/输入。
    if (!_synced) {
      _workerCtrl.text = settings.defaultWorkerName;
      _vehicleCtrl.text = settings.defaultVehicleNo;
      _yardCtrl.text = settings.yardName;
      _synced = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('个人信息'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '「默认姓名」即 Excel 导入时的目标人：导入表格只识别并导入该姓名对应的记录；清空姓名则可导入全部人员。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: '默认姓名',
                  controller: _workerCtrl,
                  onChanged:
                      (v) => ref
                          .read(appSettingsProvider.notifier)
                          .updateDefaultWorkerName(v.trim()),
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: '默认车号',
                  controller: _vehicleCtrl,
                  onChanged:
                      (v) => ref
                          .read(appSettingsProvider.notifier)
                          .updateDefaultVehicleNo(v.trim()),
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: '货场名称',
                  controller: _yardCtrl,
                  onChanged:
                      (v) => ref
                          .read(appSettingsProvider.notifier)
                          .updateYardName(v.trim()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      // 让首页当前记录重新加载，立即反映默认姓名/车号/货场名
                      ref.invalidate(selectedDateRecordProvider);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('个人信息已保存')));
                    },
                    child: const Text('保存个人信息'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JobTypePriceSection extends ConsumerStatefulWidget {
  const _JobTypePriceSection();

  @override
  ConsumerState<_JobTypePriceSection> createState() =>
      _JobTypePriceSectionState();
}

class _JobTypePriceSectionState extends ConsumerState<_JobTypePriceSection> {
  /// 每个作业类型对应一个 Controller，用于失焦/外部点击时读取当前输入值。
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};

  /// 每个作业类型独立的 FocusNode，用于判断输入框是否正在编辑（避免外部刷新覆盖输入）。
  final Map<String, FocusNode> _priceFocusNodes = {};

  /// 每个作业类型独立的防抖 Timer，避免多个单价框互相取消保存。
  final Map<String, Timer> _priceDebounces = {};

  /// 整块「作业类型与单价」是否展开，默认收起以节省设置页竖向空间。
  bool _expanded = false;

  @override
  void dispose() {
    for (final t in _priceDebounces.values) {
      t.cancel();
    }
    _priceDebounces.clear();
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    for (final f in _priceFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _savePrice(String jobType, String value) {
    final price = double.tryParse(value);
    if (price == null) return;
    ref.read(unitPricesProvider.notifier).setPrice(jobType, price);
  }

  void _saveName(String oldName, String value) {
    final newName = value.trim();
    if (newName.isEmpty || newName == oldName) return;
    ref.read(unitPricesProvider.notifier).rename(oldName, newName);
  }

  @override
  Widget build(BuildContext context) {
    final unitPrices = ref.watch(unitPricesProvider);
    final entries = unitPrices.entries.toList();

    // 清理已删除作业类型的 Controller / 防抖 Timer，避免内存泄漏。
    final currentKeys = unitPrices.keys.toSet();
    _nameControllers.removeWhere((key, ctrl) {
      if (!currentKeys.contains(key)) {
        ctrl.dispose();
        return true;
      }
      return false;
    });
    _priceControllers.removeWhere((key, ctrl) {
      if (!currentKeys.contains(key)) {
        ctrl.dispose();
        return true;
      }
      return false;
    });
    _priceDebounces.removeWhere((key, timer) {
      if (!currentKeys.contains(key)) {
        timer.cancel();
        return true;
      }
      return false;
    });
    _priceFocusNodes.removeWhere((key, focus) {
      if (!currentKeys.contains(key)) {
        focus.dispose();
        return true;
      }
      return false;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SectionHeader(
            '作业类型与单价（元/车）',
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_expanded)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '暂无作业类型，可在下方添加',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final e in entries)
                    Builder(
                      builder: (_) {
                        final jobType = e.key;
                        final price = e.value;
                        final nameCtrl = _nameControllers.putIfAbsent(
                          jobType,
                          () => TextEditingController(text: jobType),
                        );
                        final priceCtrl = _priceControllers.putIfAbsent(
                          jobType,
                          () => TextEditingController(
                            text: price.toStringAsFixed(2),
                          ),
                        );
                        final priceFocus = _priceFocusNodes.putIfAbsent(
                          jobType,
                          () => FocusNode(),
                        );
                        // 外部单价变化（导入/其他途径）时同步输入框，但不打断正在编辑。
                        if (!priceFocus.hasFocus &&
                            priceCtrl.text != price.toStringAsFixed(2)) {
                          priceCtrl.text = price.toStringAsFixed(2);
                        }

                        return Padding(
                          key: ValueKey(jobType),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: DefaultJobTypes.colorOf(jobType),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '作业类型',
                                    filled: true,
                                  ),
                                  onFieldSubmitted:
                                      (v) => _saveName(jobType, v),
                                  onEditingComplete:
                                      () => _saveName(jobType, nameCtrl.text),
                                  onTapOutside:
                                      (_) => _saveName(jobType, nameCtrl.text),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: priceCtrl,
                                  focusNode: priceFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    labelText: '单价',
                                    filled: true,
                                  ),
                                  onChanged: (v) {
                                    _priceDebounces[jobType]?.cancel();
                                    _priceDebounces[jobType] = Timer(
                                      const Duration(milliseconds: 500),
                                      () {
                                        if (!mounted) return;
                                        _savePrice(jobType, v);
                                        _priceDebounces.remove(jobType);
                                      },
                                    );
                                  },
                                  onFieldSubmitted: (v) {
                                    _priceDebounces[jobType]?.cancel();
                                    _priceDebounces.remove(jobType);
                                    _savePrice(jobType, v);
                                  },
                                  onEditingComplete: () {
                                    _priceDebounces[jobType]?.cancel();
                                    _priceDebounces.remove(jobType);
                                    _savePrice(jobType, priceCtrl.text);
                                  },
                                  onTapOutside: (_) {
                                    _priceDebounces[jobType]?.cancel();
                                    _priceDebounces.remove(jobType);
                                    _savePrice(jobType, priceCtrl.text);
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed:
                                    () => ref
                                        .read(unitPricesProvider.notifier)
                                        .remove(jobType),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 8),
                  const _AddJobTypeCard(),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AddJobTypeCard extends ConsumerStatefulWidget {
  const _AddJobTypeCard();

  @override
  ConsumerState<_AddJobTypeCard> createState() => _AddJobTypeCardState();
}

class _AddJobTypeCardState extends ConsumerState<_AddJobTypeCard> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    if (name.isNotEmpty) {
      try {
        await ref.read(unitPricesProvider.notifier).add(name, price);
      } catch (e) {
        if (!mounted) return;
        final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      // 手动添加的类型若命中「其他作业类型」（固定高级类型），自动解锁显示，
      // 避免「设置页加了、首页却看不到」的脱节。
      if (DefaultJobTypes.advancedJobTypes.contains(name)) {
        ref.read(appSettingsProvider.notifier).revealAdvancedTypes({name});
      }
      _nameCtrl.clear();
      _priceCtrl.clear();
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 默认收起的入口，点开才显示表单，避免占用过多竖向空间
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '新增作业类型',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: '类型名称',
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _priceCtrl,
                          decoration: const InputDecoration(
                            labelText: '单价',
                            filled: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _add,
                      child: const Text('添加类型'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SalarySection extends ConsumerWidget {
  const _SalarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salary = ref.watch(salarySettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('工资构成设置'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _NumberField(
                  label: '基本底薪',
                  value: salary.baseSalary,
                  onChanged:
                      (v) => _update(ref, salary.copyWith(baseSalary: v)),
                ),
                _NumberField(
                  label: '餐补',
                  value: salary.mealAllowance,
                  onChanged:
                      (v) => _update(ref, salary.copyWith(mealAllowance: v)),
                ),
                _NumberField(
                  label: '加班',
                  value: salary.overtime,
                  onChanged: (v) => _update(ref, salary.copyWith(overtime: v)),
                ),
                _NumberField(
                  label: '工龄/奖金',
                  value: salary.seniorityBonus,
                  onChanged:
                      (v) => _update(ref, salary.copyWith(seniorityBonus: v)),
                ),
                _NumberField(
                  label: '扣款',
                  value: salary.deduction,
                  onChanged: (v) => _update(ref, salary.copyWith(deduction: v)),
                ),
                const SizedBox(height: 12),
                // 工资构成实时合计（不含计件收入），随输入即时刷新
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '工资构成合计（不含计件）',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        '¥${salary.totalSalary(0).toStringAsFixed(2)}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('工资设置已保存')));
                    },
                    child: const Text('保存工资设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _update(WidgetRef ref, SalarySettings settings) {
    ref.read(salarySettingsProvider.notifier).update(settings);
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('外观设置'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题颜色',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: List.generate(AppTheme.primaries.length, (i) {
                    final color = AppTheme.primaries[i];
                    final selected = settings.primaryColorIndex == i;
                    return InkWell(
                      onTap:
                          () => ref
                              .read(appSettingsProvider.notifier)
                              .updatePrimaryColorIndex(i),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border:
                              selected
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                          boxShadow:
                              selected
                                  ? [
                                    BoxShadow(
                                      color: color.withOpacity(0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                  : null,
                        ),
                        child:
                            selected
                                ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                                : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '隐藏金额',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Switch(
                      value: settings.hideAmount,
                      onChanged:
                          (v) => ref
                              .read(appSettingsProvider.notifier)
                              .updateHideAmount(v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '深色模式',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Switch(
                      value: themeMode == 'dark',
                      onChanged: (v) {
                        final mode = v ? 'dark' : 'light';
                        ref.read(themeModeProvider.notifier).state = mode;
                        ref.read(settingsRepositoryProvider).setThemeMode(mode);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetSection extends ConsumerStatefulWidget {
  const _TargetSection();

  @override
  ConsumerState<_TargetSection> createState() => _TargetSectionState();
}

class _TargetSectionState extends ConsumerState<_TargetSection> {
  final _dailyCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  bool _synced = false;

  @override
  void dispose() {
    _dailyCtrl.dispose();
    _monthlyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    if (!_synced) {
      _dailyCtrl.text = settings.dailyTargetVehicles.toString();
      _monthlyCtrl.text = settings.monthlyTargetVehicles.toString();
      _synced = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('目标与参数'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SettingsTextField(
                  label: '每日目标车数',
                  controller: _dailyCtrl,
                  keyboardType: TextInputType.number,
                  onChanged:
                      (v) => ref
                          .read(appSettingsProvider.notifier)
                          .updateDailyTarget(int.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 12),
                _SettingsTextField(
                  label: '每月目标车数',
                  controller: _monthlyCtrl,
                  keyboardType: TextInputType.number,
                  onChanged:
                      (v) => ref
                          .read(appSettingsProvider.notifier)
                          .updateMonthlyTarget(int.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref.invalidate(selectedDateRecordProvider);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('目标设置已保存')));
                    },
                    child: const Text('保存目标设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OcrSection extends ConsumerStatefulWidget {
  const _OcrSection();

  @override
  ConsumerState<_OcrSection> createState() => _OcrSectionState();
}

class _OcrSectionState extends ConsumerState<_OcrSection> {
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String _model = 'qwen-vl-plus';
  bool _obscure = true;
  bool _busy = false;
  bool _synced = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(secureSettingsRepositoryProvider);
    final key = await repo.getApiKey() ?? '';
    final url = await repo.getBaseUrl();
    final model = await repo.getModel();
    if (!mounted) return;
    setState(() {
      _keyCtrl.text = key;
      _urlCtrl.text = url;
      _model = model;
      _synced = true;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(secureSettingsRepositoryProvider);
      await repo.saveAll(
        apiKey: _keyCtrl.text.trim(),
        baseUrl: _urlCtrl.text.trim().isEmpty
            ? 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
            : _urlCtrl.text.trim(),
        model: _model,
      );
      // 失效相关 provider 以便对账页重新加载
      ref.invalidate(qwenApiKeyProvider);
      ref.invalidate(qwenVlEngineOrNullProvider);
      ref.invalidate(qwenApiKeyConfiguredProvider);
      if (mounted) _snack('已保存（API Key 已加密存至 Android Keystore）');
    } catch (e) {
      if (mounted) _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_keyCtrl.text.trim().isEmpty) {
      _snack('请先填入 API Key');
      return;
    }
    setState(() => _busy = true);
    try {
      // 临时构造一个引擎测试（不保存）
      final engine = QwenVlOcrEngine(
        apiKey: _keyCtrl.text.trim(),
        baseUrl: _urlCtrl.text.trim().isEmpty
            ? 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
            : _urlCtrl.text.trim(),
        model: _model,
      );
      final ok = await engine.testConnection();
      engine.dispose();
      if (mounted) {
        _snack(ok ? '✓ 连接成功' : '✗ 连接失败，请检查 Key / 模型名 / 网络');
      }
    } catch (e) {
      if (mounted) _snack('测试失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_synced) {
      // 首次构建异步加载已有配置
      _load();
    }
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('云端识别 / OCR'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置阿里云通义千问 Qwen-VL API 后，对账页开启「高精度」即可让云端大模型直接读表，'
                  '跳过行级 OCR + 网格解析器，准确率大幅提升（密集表 + 紫底加班 cell 尤为明显）。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: cs.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '图片会上传至阿里云 DashScope 进行识别。Key 通过 Android Keystore 加密存储。',
                          style: TextStyle(fontSize: 12, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key（DashScope / 百炼）',
                    hintText: 'sk-xxxxxxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: '默认百炼兼容端点，无需修改',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _model,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'qwen-vl-plus',
                      child: Text('qwen-vl-plus · 性价比（推荐）'),
                    ),
                    DropdownMenuItem(
                      value: 'qwen-vl-max',
                      child: Text('qwen-vl-max · 最准（费用高）'),
                    ),
                    DropdownMenuItem(
                      value: 'qwen2.5-vl-72b-instruct',
                      child: Text('qwen2.5-vl-72b-instruct · 开源大杯'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _model = v);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _test,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('测试连接'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '获取 Key：阿里云 → 百炼大模型平台 → API-Key 管理 → 创建我的 API-Key',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  String get _stamp {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}'
        '_${n.hour.toString().padLeft(2, '0')}'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String content) async {
    final r = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
    );
    return r ?? false;
  }

  /// 统一处理「忙碌状态 + 异常捕获」，子任务自行弹出成功提示。
  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('数据安全与备份'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _BackupButton(
                  label: '导出 JSON 备份',
                  loading: _busy,
                  onPressed:
                      () => _run(() async {
                        final repo = ref.read(recordRepositoryProvider);
                        final srepo = ref.read(settingsRepositoryProvider);
                        final records = repo.getAllRecords();
                        if (records.isEmpty) {
                          if (mounted) _snack('暂无记录可导出');
                          return;
                        }
                        final backup = FullBackup(
                          records: records,
                          jobPrices: srepo.getUnitPrices(),
                          salarySettings: srepo.getSalarySettings(),
                          appSettings: srepo.getAppSettings(),
                          fixedWorkers: srepo.getFixedWorkers(),
                          importTemplate: srepo.getImportTemplate(),
                        );
                        // L2：payload 在主线程廉价构造，jsonEncode 放到独立 isolate，
                        // 避免多年数据构造超大 JSON 时阻塞主线程卡 UI。
                        final payload = RecordSerialization.fullBackupPayload(
                          backup,
                        );
                        // L2：payload 在主线程廉价构造，jsonEncode 放到独立 isolate，
                        // 避免多年数据构造超大 JSON 时阻塞主线程卡 UI。
                        final json = await compute(jsonEncodePayload, payload);
                        await shareTextFile(json, '货场记账备份_$_stamp.json');
                        if (mounted) {
                          _snack('已导出 ${records.length} 条记录及全部配置');
                        }
                      }),
                ),
                _BackupButton(
                  label: '从 JSON 恢复',
                  loading: _busy,
                  onPressed:
                      () => _run(() async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        final path = picked?.files.single.path;
                        if (path == null) return;
                        // M4 防护：拒绝超大备份文件，避免整文件读入内存后 OOM。
                        final file = File(path);
                        if (file.lengthSync() > 50 * 1024 * 1024) {
                          if (mounted) {
                            _snack('备份文件过大（>50MB），已拒绝解析以防内存溢出');
                          }
                          return;
                        }
                        final content = await file.readAsString();
                        // S2 加固：畸形/损坏的备份文件解析可能抛异常，包一层 try/catch
                        // 给出友好提示而非让 App 崩溃（可用性/DoS 防护）。
                        final FullBackup backup;
                        try {
                          backup = RecordSerialization.parseFullBackup(content);
                        } catch (e) {
                          debugPrint('备份解析失败: $e');
                          if (mounted) {
                            _snack('备份文件解析失败，可能不是有效的备份文件');
                          }
                          return;
                        }
                        if (backup.records.isEmpty && !backup.hasSettings) {
                          if (mounted) _snack('文件中没有有效数据');
                          return;
                        }
                        final ok = await _confirm(
                          '恢复备份',
                          '将用 ${backup.records.length} 条记录覆盖当前全部数据，'
                              '并恢复单价/工资构成/设置等全部配置，确定继续？',
                        );
                        if (!ok) return;
                        final repo = ref.read(recordRepositoryProvider);
                        final srepo = ref.read(settingsRepositoryProvider);
                        await repo.replaceAllRecords(backup.records);
                        if (backup.jobPrices != null) {
                          await srepo.replaceAllPrices(backup.jobPrices!);
                        }
                        if (backup.salarySettings != null) {
                          await srepo.saveSalarySettings(
                            backup.salarySettings!,
                          );
                        }
                        if (backup.appSettings != null) {
                          await srepo.saveAppSettings(backup.appSettings!);
                        }
                        if (backup.fixedWorkers != null) {
                          await srepo.setFixedWorkers(backup.fixedWorkers!);
                        }
                        if (backup.importTemplate != null) {
                          await srepo.saveImportTemplate(
                            backup.importTemplate!,
                          );
                        }
                        // H2：失效全量快照根即可级联刷新所有派生 Provider；
                        // 配置类 Provider（单价/工资/应用设置/主题）单独刷新。
                        ref.invalidate(allRecordsProvider);
                        ref.invalidate(selectedDateRecordProvider);
                        ref.invalidate(unitPricesProvider);
                        ref.invalidate(salarySettingsProvider);
                        ref.invalidate(appSettingsProvider);
                        ref.invalidate(themeModeProvider);
                        if (mounted) {
                          _snack('已恢复 ${backup.records.length} 条记录及全部配置');
                        }
                      }),
                ),
                _BackupButton(
                  label: '恢复示例数据',
                  loading: _busy,
                  onPressed:
                      () => _run(() async {
                        final ok = await _confirm(
                          '恢复示例数据',
                          '将写入 3 条示例记录（已存在的日期会被覆盖），确定？',
                        );
                        if (!ok) return;
                        await ref
                            .read(recordRepositoryProvider)
                            .seedSampleData();
                        ref.invalidate(allRecordsProvider);
                        ref.invalidate(selectedDateRecordProvider);
                        if (mounted) _snack('已写入示例数据');
                      }),
                ),
                _BackupButton(
                  label: '清空全部数据',
                  foregroundColor: Theme.of(context).colorScheme.error,
                  loading: _busy,
                  onPressed:
                      () => _run(() async {
                        final ok = await _confirm(
                          '清空全部数据',
                          '将删除所有记账记录，且不可恢复，确定？',
                        );
                        if (!ok) return;
                        await ref
                            .read(recordRepositoryProvider)
                            .clearAllRecords();
                        // H2：失效全量快照根即可级联刷新所有派生 Provider
                        ref.invalidate(allRecordsProvider);
                        ref.invalidate(selectedDateRecordProvider);
                        if (mounted) _snack('已清空全部数据');
                      }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackupButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final bool loading;

  const _BackupButton({
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child:
            loading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(label),
      ),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _SettingsTextField({
    required this.label,
    this.controller,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: value.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(filled: true),
              onChanged:
                  (v) => onChanged(
                    v.trim().isEmpty ? 0 : (double.tryParse(v) ?? value),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

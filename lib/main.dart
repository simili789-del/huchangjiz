import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/job_types.dart';
import 'core/theme/app_theme.dart';
import 'core/util/share_file.dart';
import 'domain/entities/app_settings.dart';
import 'domain/entities/salary_settings.dart';
import 'domain/entities/work_record.dart';
import 'presentation/providers/app_settings_provider.dart';
import 'presentation/providers/repository_providers.dart';
import 'presentation/root_shell.dart';

/// 首次启动默认作业类型单价
const _defaultPrices = DefaultJobTypes.defaultPrices;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // M5：启动时清理历史分享临时文件残留，避免缓存目录无限累积。
  await cleanupStaleShareFiles();

  // 捕获异步异常，避免初始化失败时白屏无任何提示
  runZonedGuarded(() async {
    await Hive.initFlutter();

    // 注册适配器（防重复注册）
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(WorkRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ShiftTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(SalarySettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }

    // 确保所有 Box 打开完成后再启动 App
    await Future.wait([
      Hive.openBox<WorkRecord>(HiveBoxes.records),
      Hive.openBox(HiveBoxes.jobPrices),
      Hive.openBox<SalarySettings>(HiveBoxes.salarySettings),
      Hive.openBox(HiveBoxes.appSettings),
      Hive.openBox<AppSettings>(HiveBoxes.appSettingsV2),
      Hive.openBox('reconciliation_drafts'), // 对账识别草稿（非类型化，存 JSON）
    ]);

    // 首次启动：初始化默认作业类型单价（box 为空时写入）
    final priceBox = Hive.box(HiveBoxes.jobPrices);
    if (priceBox.isEmpty) {
      for (final entry in _defaultPrices.entries) {
        await priceBox.put(entry.key, entry.value);
      }
    }

    // 作业类型名迁移：把历史遗留的旧名统一改为新标准名，
    // 避免老数据里「内倒归剁」等旧名与新规范并存导致单价不一致。
    // 迁移映射：旧名 → 新名（价格保留旧值；若新名已存在则取较高价）。
    // 注：「外倒装车」自 2026-08 起成为标准类型名（原标准名为「货场倒货」），
    // 故不再需要把「外倒装车」迁到「货场倒货」；历史「货场倒货」记录保留旧名分组。
    const migrationMap = {
      '内倒归剁': '内倒归垛',
      '货场归垛': '货场归剁',
      '归垛': '货场归剁',
      '归剁': '货场归剁',
    };
    for (final entry in migrationMap.entries) {
      final oldKey = entry.key;
      final newKey = entry.value;
      if (priceBox.containsKey(oldKey)) {
        final oldPrice = (priceBox.get(oldKey) as num).toDouble();
        final newPrice = priceBox.containsKey(newKey)
            ? math.max(oldPrice, (priceBox.get(newKey) as num).toDouble())
            : oldPrice;
        await priceBox.put(newKey, newPrice);
        await priceBox.delete(oldKey);
      }
    }
    // 补全默认类型：确保新规范里的标准类型都有单价（缺则写默认值）
    for (final entry in _defaultPrices.entries) {
      if (!priceBox.containsKey(entry.key)) {
        await priceBox.put(entry.key, entry.value);
      }
    }

    runApp(const ProviderScope(child: YardAccountingApp()));
  }, (error, stack) {
    // 初始化失败也启动 App，展示错误页而非白屏
    debugPrint('初始化失败: $error\n$stack');
    runApp(const MaterialApp(
      home: Material(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              // S3：生产环境不向用户暴露内部异常文本（可能含路径/类型信息），
              // 详细异常仅通过 debugPrint 输出（见上方 onError）。
              '初始化失败，请重启 App。若持续失败，请联系开发团队获取支持。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ),
      ),
    ));
  });
}

class YardAccountingApp extends ConsumerWidget {
  const YardAccountingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final primaryIndex = appSettings.primaryColorIndex;

    return MaterialApp(
      title: '货场作业记账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(primaryIndex),
      darkTheme: AppTheme.dark(primaryIndex),
      themeMode: switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const RootShell(),
    );
  }
}

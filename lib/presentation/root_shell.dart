import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'pages/history/history_page.dart';
import 'pages/home/home_page.dart';
import 'pages/import/import_wizard_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/stats/stats_page.dart';
import 'providers/import_provider.dart';

/// 四大模块入口：今日记账 / 明细查询 / 月报统计 / 设置管理
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  /// 分享流订阅（M6 修复：dispose 时取消，避免根组件重建时泄漏）。
  StreamSubscription<List<SharedMediaFile>>? _mediaSub;

  static const _pages = [
    HomePage(),
    HistoryPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initSharing();
  }

  /// 监听微信/系统分享进来的文件，命中表格则存入 sharedFileProvider 待跳转。
  void _initSharing() {
    final notifier = ref.read(sharedFileProvider.notifier);

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _consume(files, notifier);
      ReceiveSharingIntent.instance.reset(); // 清除冷启动缓存，避免重复触发
    });

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _consume(files, notifier);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  void _consume(List<SharedMediaFile> files, StateController<String?> notifier) {
    for (final f in files) {
      final p = f.path;
      if (isImportableFile(p)) {
        notifier.state = p;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 分享文件到达即跳转向导，并消费置空防止重复触发
    ref.listen<String?>(sharedFileProvider, (prev, next) {
      if (next != null && isImportableFile(next)) {
        ref.read(sharedFileProvider.notifier).state = null;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImportWizardPage(filePath: next)),
        );
      }
    });

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '今日'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: '明细'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: '月报'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}

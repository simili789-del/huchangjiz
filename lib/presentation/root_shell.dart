import 'dart:ui';

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

    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _consume(files, notifier);
    }, onError: (_) {});
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      // 悬浮玻璃导航栏：与页面内容之间留白，磨砂玻璃材质呼应整体拟态风格。
      // 仅为视觉包装，导航逻辑（selectedIndex/onDestinationSelected）保持不变。
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.18)
                      : Colors.white.withOpacity(0.75),
                  width: 1.2,
                ),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                backgroundColor: Colors.transparent,
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined), label: '今日'),
                  NavigationDestination(
                      icon: Icon(Icons.list_alt_outlined), label: '明细'),
                  NavigationDestination(
                      icon: Icon(Icons.bar_chart_outlined), label: '月报'),
                  NavigationDestination(
                      icon: Icon(Icons.settings_outlined), label: '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

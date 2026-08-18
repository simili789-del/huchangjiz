import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_settings_provider.dart';
import '../providers/repository_providers.dart';
import '../providers/selected_date_record_provider.dart';

/// 统一顶部栏：Logo + 货场名称 + 日期 + 撤销/主题操作。
///
/// 直接返回真实 [AppBar]，由其统一处理状态栏安全区、背景与固定高度，
/// 避免自定义控件当 appBar 使用时各页面高度/背景不一致导致的「错行」。
class YardAppBar extends ConsumerWidget implements PreferredSizeWidget {
  /// 作为 Scaffold.appBar 使用时必须提供固定高度（与下方 toolbarHeight 保持一致）。
  @override
  final Size preferredSize = const Size.fromHeight(64);

  final List<Widget>? actions;

  const YardAppBar({super.key, this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final now = DateTime.now();
    const weekDays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekDay = weekDays[now.weekday - 1];

    return AppBar(
      // 根页面无需返回按钮
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '记',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  settings.yardName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${DateFormat('yyyy年M月d日').format(now)} $weekDay',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ...?actions,
        IconButton(
          icon: const Icon(Icons.undo_outlined),
          tooltip: '撤销',
          onPressed: () {
            final notifier = ref.read(selectedDateRecordProvider.notifier);
            if (notifier.canUndo) {
              notifier.undo();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已撤销上一步')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('没有可撤销的操作')),
              );
            }
          },
        ),
        IconButton(
          icon: Icon(
            themeMode == 'dark' ? Icons.dark_mode : Icons.wb_sunny_outlined,
          ),
          tooltip: '切换主题',
          onPressed: () {
            final next = themeMode == 'light'
                ? 'dark'
                : themeMode == 'dark'
                    ? 'system'
                    : 'light';
            ref.read(themeModeProvider.notifier).state = next;
            ref.read(settingsRepositoryProvider).setThemeMode(next);
          },
        ),
      ],
    );
  }
}

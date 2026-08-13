import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:yard_accounting/core/constants/job_types.dart';
import 'package:yard_accounting/domain/entities/app_settings.dart';
import 'package:yard_accounting/domain/entities/salary_settings.dart';
import 'package:yard_accounting/domain/entities/work_record.dart';
import 'package:yard_accounting/presentation/root_shell.dart';

Future<void> main() async {
  // 四大模块页面在 build 时会通过 Riverpod 访问 Hive Box，
  // 因此测试前必须像 main() 一样初始化 Hive 并注册适配器、开箱，
  // 否则 Hive.box() 会抛 HiveError 导致 flutter test 失败、CI 不出包。
  //
  // 注意：不能用 Hive.initFlutter()——它内部调 path_provider 插件，
  // 单元测试环境无该插件实现会抛 MissingPluginException。
  // 改用 Hive.init() + 系统临时目录，纯 Dart 实现，无插件依赖。
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 测试环境无原生插件实现，拦截 receive_sharing_intent 通道的方法/事件调用，
    // 避免 RootShell.initState 里的 getInitialMedia / getMediaStream 抛 MissingPluginException：
    // - getInitialMedia -> 返回空列表（没有分享进来的文件）
    // - EventChannel 的 listen/cancel -> 返回 null（不发射任何事件，避免流异常）
    const sharingChannel = MethodChannel('receive_sharing_intent');
    sharingChannel.setMockMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'getInitialMedia':
          return <dynamic>[];
        default:
          return null;
      }
    });
    final tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ShiftTypeAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(WorkRecordAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SalarySettingsAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(AppSettingsAdapter());
    await Future.wait([
      Hive.openBox<WorkRecord>(HiveBoxes.records),
      Hive.openBox(HiveBoxes.jobPrices),
      Hive.openBox<SalarySettings>(HiveBoxes.salarySettings),
      Hive.openBox(HiveBoxes.appSettings),
      Hive.openBox<AppSettings>(HiveBoxes.appSettingsV2),
    ]);
  });

  testWidgets('底部导航包含四大模块入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RootShell()),
      ),
    );

    // 底部导航真实标签为「今日 / 明细 / 月报 / 设置」
    // （见 lib/presentation/root_shell.dart 中 NavigationBar 的 destinations）。
    // 注意：必须限定在 NavigationBar 内匹配，因为「设置」字样在设置页内部也会出现，
    // 直接用 find.text('设置') 会匹配到多个而误判失败。
    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);
    expect(
      find.descendant(of: navBar, matching: find.byType(NavigationDestination)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: navBar, matching: find.text('今日')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('明细')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('月报')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('设置')),
      findsOneWidget,
    );
  });
}

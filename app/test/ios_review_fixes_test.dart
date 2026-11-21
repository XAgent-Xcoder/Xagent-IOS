// 终审修复轮：抽屉主机图标不再开本地引擎页（I-1）、快捷面板无引擎项（I-1b/M-3）、
// 权限页手机卡整卡隐藏（I-2）、BlockedFeaturePage 有返回（I-3）、
// 聊天空状态在未选择时给远程引导（I-4）、主机状态不再显示"未安装"（M-1）。
//
//   flutter test test/ios_review_fixes_test.dart

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/onboarding_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_app/ui/shell/page_frame.dart';
import 'package:dsh_app/ui/engine/engine_screen.dart';
import 'package:dsh_app/ui/features/permission_page.dart';
import 'package:dsh_app/ui/remote/remote_screen.dart';
import 'package:dsh_app/ui/shell/home_shell.dart';
import 'package:dsh_app/ui/shell/quick_panel.dart';
import 'package:dsh_app/ui/settings/blocked_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'chat/support/harness.dart';
import 'phone/support.dart' show FixedActiveHost, FixedHosts;
import 'shell/golden_harness.dart';

const _bundled = 'r5-dsh0.2.1-rc.2-node24.22.1-ubuntu24.04.5-b3f6c96ee2f2';
const _missing = RuntimeStatus(phase: RuntimePhase.notInstalled, bundledVersion: _bundled, abi: 'arm64-v8a');

List<Override> _iosLocal({HostRef host = HostRef.local}) => [
  isIosProvider.overrideWithValue(true),
  localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: _missing))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  activeHostProvider.overrideWith(() => FixedActiveHost(host)),
  hostsProvider.overrideWith(FixedHosts.new),
  networkKicksProvider.overrideWithValue(const Stream.empty()),
];

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(
      home: home,
      brightness: Brightness.light,
      prefs: const OnboardingPrefs(loaded: true, welcomeSeen: true),
      overrides: overrides,
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('I-1: iOS 点抽屉主机图标不开本地引擎页（改开主机表）', (tester) async {
    await _pump(tester, HomeShell(chatBuilder: (_) => const SizedBox.expand(), initiallyOpen: true), _iosLocal());
    await tester.tap(find.byKey(const ValueKey('identity-host-details')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EngineScreen), findsNothing);
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('I-1b/M-3: iOS 快捷面板无引擎项', (tester) async {
    await _pump(tester, QuickPanel(motion: const AlwaysStoppedAnimation(1.0), onOpen: (_) {}), _iosLocal());
    expect(find.text('本机引擎'), findsNothing);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('I-2: iOS+local 权限页无手机卡', (tester) async {
    final harness = ChatHarness(
      connected: false,
      extra: [isIosProvider.overrideWithValue(true), activeHostProvider.overrideWith(() => FixedActiveHost(HostRef.local))],
    );
    usePhoneView(tester);
    await tester.pumpWidget(
      testApp(const PermissionPage(), brightness: Brightness.light, overrides: harness.overrides),
    );
    await pumpFrames(tester, 8);
    expect(find.text('访问手机文件'), findsNothing);
    expect(find.text('手机操控确认'), findsNothing);
  });

  testWidgets('I-3: BlockedFeaturePage 有页框（可返回）', (tester) async {
    await _pump(tester, const BlockedFeaturePage(), _iosLocal());
    // AppPage 框带返回手势/标题栏；不再是被推路由里无出口的裸 Scaffold。
    expect(find.byType(AppPage), findsOneWidget);
  });

  testWidgets('I-4: iOS+local 聊天空状态给远程引导，不是"引擎未连接"', (tester) async {
    final harness = ChatHarness(
      connected: false,
      extra: [isIosProvider.overrideWithValue(true), activeHostProvider.overrideWith(() => FixedActiveHost(HostRef.local))],
    );
    usePhoneView(tester);
    await tester.pumpWidget(
      testApp(
        const ChatScreen(),
        brightness: Brightness.light,
        overrides: [
          activeConnectionProvider.overrideWithValue(const AsyncData<HostConnection?>(null)),
          ...harness.overrides.skip(1),
        ],
      ),
    );
    await pumpFrames(tester, 8);
    expect(find.text('引擎未连接'), findsNothing);
    expect(find.text('连接电脑或服务器'), findsOneWidget);
  });

  testWidgets('M-1: iOS+local 抽屉状态行不显示"未安装"', (tester) async {
    await _pump(tester, HomeShell(chatBuilder: (_) => const SizedBox.expand(), initiallyOpen: true), _iosLocal());
    expect(find.textContaining('未安装'), findsNothing);
  });
}

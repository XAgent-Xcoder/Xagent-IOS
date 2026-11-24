// Task 3：iOS 上主机为 local（未选择）时，聊天与抽屉的空状态统一显示远程
// 引导，不出现本地安装/启动入口；ready 完成前保持启动画面不闪引导；
// 恢复远程主机直接进远程流程；连接失败仍显示该远程主机（失败≠未选择）。
//
//   flutter test test/ios_unselected_host_state_test.dart

import 'dart:async';

import 'package:xagent/runtime/runtime_bridge.dart';
import 'package:xagent/runtime/runtime_state.dart';
import 'package:xagent/state/connection_state.dart';
import 'package:xagent/state/hosts_state.dart';
import 'package:xagent/state/onboarding_state.dart';
import 'package:xagent/state/platform_state.dart';
import 'package:xagent/state/sessions_state.dart';
import 'package:xagent/state/settings_state.dart';
import 'package:xagent/ui/chat/chat_screen.dart';
import 'package:xagent/ui/shell/home_shell.dart';
import 'package:xagent/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'chat/support/harness.dart' show ChatHarness, testApp, pumpFrames, usePhoneView;
import 'phone/support.dart' show FixedActiveHost, FixedHosts;
import 'shell/golden_harness.dart';

const _lab = HostRef.ssh('lab');
const _bundled = 'r5-dsh0.2.1-rc.2-node24.22.1-ubuntu24.04.5-b3f6c96ee2f2';
const _missing = RuntimeStatus(phase: RuntimePhase.notInstalled, bundledVersion: _bundled, abi: 'arm64-v8a');

List<Override> _overrides({
  required bool isIos,
  HostRef active = HostRef.local,
  bool readyHangs = false,
  HostLinkPhase link = HostLinkPhase.idle,
}) => [
  isIosProvider.overrideWithValue(isIos),
  localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: _missing))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  sessionsProvider.overrideWith(() => FakeSessions(const [])),
  activeHostProvider.overrideWith(() => readyHangs ? HangingActiveHost(active) : FixedActiveHost(active)),
  hostsProvider.overrideWith(FixedHosts.new),
  hostLinkStatusProvider.overrideWith((ref, host) => Stream.value(HostLinkStatus(link))),
  networkKicksProvider.overrideWithValue(const Stream.empty()),
];

/// ready 永不完成：模拟主机恢复还在进行。
class HangingActiveHost extends FixedActiveHost {
  HangingActiveHost(super.host);

  @override
  Future<void> get ready => Completer<void>().future;
}

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

/// 抽屉全开的首页：空状态与主机标识都在。
HomeShell _homeWithDrawer() => HomeShell(chatBuilder: (_) => const SizedBox.expand(), initiallyOpen: true);

void main() {
  testWidgets('iOS+local：抽屉空状态是远程引导，无本地安装/启动入口', (tester) async {
    await _pump(tester, _homeWithDrawer(), _overrides(isIos: true));
    expect(find.text('未选择主机'), findsWidgets);
    expect(find.textContaining('安装运行环境'), findsNothing);
    expect(find.textContaining('启动引擎'), findsNothing);
    expect(find.textContaining('在手机上接着用电脑'), findsOneWidget); // remoteHostsIntro 引导文案
  });

  testWidgets('iOS+local：聊天空状态无本地安装/启动 pill', (tester) async {
    final harness = ChatHarness(
      connected: false,
      runtime: () => FakeRuntime(const LocalRuntimeState(loaded: true, status: _missing)),
      extra: [isIosProvider.overrideWithValue(true), activeHostProvider.overrideWith(() => FixedActiveHost(HostRef.local))],
    );
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const ChatScreen(), brightness: Brightness.light, overrides: harness.overrides));
    await pumpFrames(tester, 8);
    expect(find.text('安装运行环境'), findsNothing);
    expect(find.text('启动引擎'), findsNothing);
  });

  testWidgets('ready 前保持启动画面，不闪引导', (tester) async {
    await _pump(tester, RootGate(home: _homeWithDrawer()), _overrides(isIos: true, readyHangs: true));
    expect(find.text('连接电脑或服务器'), findsNothing);
    expect(find.text('未选择主机'), findsNothing);
  });

  testWidgets('ready 后恢复远程主机：直接进远程流程，不出未选择引导', (tester) async {
    await _pump(tester, RootGate(home: _homeWithDrawer()), _overrides(isIos: true, active: _lab));
    expect(find.textContaining('实验室服务器'), findsWidgets);
    expect(find.text('未选择主机'), findsNothing);
  });

  testWidgets('远程连接失败：仍显示该主机与重试，不是未选择引导', (tester) async {
    await _pump(tester, _homeWithDrawer(), _overrides(isIos: true, active: _lab, link: HostLinkPhase.failed));
    expect(find.textContaining('实验室服务器'), findsWidgets);
    expect(find.text('未选择主机'), findsNothing);
  });

  testWidgets('Android+local：抽屉空状态仍是本地安装引导（对照）', (tester) async {
    await _pump(tester, _homeWithDrawer(), _overrides(isIos: false));
    expect(find.textContaining('安装运行环境'), findsWidgets);
  });
}

// iOS 远程客户端：本地引擎与手机操控是安卓专属能力（PRoot 引擎、无障碍
// 操控），在 iOS 上不可用，入口应完全不渲染而不是点了无反应的死入口。
// Android 上这些入口照常出现（防止把功能锁死）。
//
//   flutter test test/ios_feature_visibility_test.dart

import 'package:dsh_app/remote/secret_store.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/account_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/common/overview_card.dart';
import 'package:dsh_app/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'account/support.dart' show FixedAccount;
import 'phone/support.dart' show FixedActiveHost, FixedHosts;
import 'shell/golden_harness.dart';

const _missing = RuntimeStatus(phase: RuntimePhase.notInstalled, abi: 'arm64-v8a');
const _lab = HostRef.ssh('lab');

List<Override> _overrides({required bool isIos}) => [
  isIosProvider.overrideWithValue(isIos),
  localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: _missing))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  accountProvider.overrideWith(() => FixedAccount(const AccountState(phase: AccountPhase.signedOut))),
  activeHostProvider.overrideWith(() => FixedActiveHost(_lab)),
  hostsProvider.overrideWith(FixedHosts.new),
  hostLinkStatusProvider.overrideWith((ref, host) => Stream.value(const HostLinkStatus(HostLinkPhase.connected))),
  networkKicksProvider.overrideWithValue(const Stream.empty()),
  secretStoreProvider.overrideWithValue(MemorySecretStore()),
];

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(goldenApp(home: const Scaffold(body: SettingsScreen()), brightness: Brightness.light, overrides: overrides));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The host section (本机引擎/远程主机/引擎参数) sits below the fold on a phone;
/// the list is lazy, so it must be scrolled into view before its tiles exist.
Future<void> _scrollToHosts(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable), const Offset(0, -600));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.drag(find.byType(Scrollable), const Offset(0, -600));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('iOS 不渲染本地引擎与手机操控入口', (tester) async {
    await _pump(tester, _overrides(isIos: true));
    // 手机操控（无障碍）在能力组，首屏即渲染。
    expect(find.text('手机操控'), findsNothing);
    // 概览卡的引擎 footer（"本机引擎 · 未安装"）是本地引擎入口，iOS 上不可用，不渲染。
    expect(find.byType(OverviewFooter), findsNothing);
    expect(find.textContaining('本机引擎 ·'), findsNothing);
    await _scrollToHosts(tester);
    // 本机引擎（PRoot）是安卓专属，iOS 上不可用。
    expect(find.text('本机引擎'), findsNothing);
    // 远程主机与引擎参数（对当前主机生效）照常出现。
    expect(find.text('远程主机'), findsOneWidget);
    expect(find.text('引擎参数'), findsOneWidget);
  });

  testWidgets('Android 仍渲染本地引擎与手机操控入口', (tester) async {
    await _pump(tester, _overrides(isIos: false));
    expect(find.text('手机操控'), findsOneWidget);
    // Android 上概览卡的引擎 footer 照常出现。
    expect(find.byType(OverviewFooter), findsOneWidget);
    await _scrollToHosts(tester);
    expect(find.text('本机引擎'), findsOneWidget);
  });
}

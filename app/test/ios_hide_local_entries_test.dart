// Task 2：iOS 主机切换器无"本机"行；iOS+local 的标识为"未选择主机"；
// 设置页"后台运行/系统权限"两瓦片（直接构造入口）iOS 隐藏。Android 全部照常。
//
//   flutter test test/ios_hide_local_entries_test.dart

import 'package:dsh_app/remote/secret_store.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/remote/host_switcher.dart';
import 'package:dsh_app/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'phone/support.dart' show FixedActiveHost, FixedHosts;
import 'shell/golden_harness.dart';

const _lab = HostRef.ssh('lab');

List<Override> _overrides({required bool isIos, HostRef active = _lab}) => [
  isIosProvider.overrideWithValue(isIos),
  localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: runningStatus))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  activeHostProvider.overrideWith(() => FixedActiveHost(active)),
  hostsProvider.overrideWith(FixedHosts.new),
  hostLinkStatusProvider.overrideWith((ref, host) => Stream.value(const HostLinkStatus(HostLinkPhase.connected))),
  networkKicksProvider.overrideWithValue(const Stream.empty()),
  secretStoreProvider.overrideWithValue(MemorySecretStore()),
];

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(goldenApp(home: home, brightness: Brightness.light, overrides: overrides));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('iOS 主机切换器无本机行', (tester) async {
    await _pump(tester, HostSheet(onManage: () {}), _overrides(isIos: true));
    // 本机行的副标题「这台手机上的 DSH」不出现；SSH 主机行照常。
    expect(find.text('本机'), findsNothing);
    expect(find.text('实验室服务器'), findsOneWidget);
  });

  testWidgets('Android 主机切换器本机行照常', (tester) async {
    await _pump(tester, HostSheet(onManage: () {}), _overrides(isIos: false));
    expect(find.text('本机'), findsOneWidget);
  });

  testWidgets('iOS+local：HostChip 标识为未选择主机', (tester) async {
    await _pump(
      tester,
      Scaffold(body: HostChip(onTap: () {})),
      _overrides(isIos: true, active: HostRef.local),
    );
    expect(find.textContaining('未选择主机'), findsOneWidget);
    expect(find.textContaining('本机'), findsNothing);
  });

  testWidgets('Android+local：HostChip 仍是本机', (tester) async {
    await _pump(
      tester,
      Scaffold(body: HostChip(onTap: () {})),
      _overrides(isIos: false, active: HostRef.local),
    );
    expect(find.textContaining('本机'), findsOneWidget);
  });

  testWidgets('iOS 设置页无后台运行/系统权限瓦片（直接构造入口）', (tester) async {
    await _pump(tester, const Scaffold(body: SettingsScreen()), _overrides(isIos: true));
    // 先滚到通用组（否则 findsNothing 是"没 build 到"的假通过）。
    await tester.drag(find.byType(Scrollable), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('隐私与分享'), findsOneWidget); // 同组邻居在场，证明已滚到
    expect(find.text('后台运行'), findsNothing);
    expect(find.text('系统权限'), findsNothing);
  });

  testWidgets('Android 设置页两瓦片照常', (tester) async {
    await _pump(tester, const Scaffold(body: SettingsScreen()), _overrides(isIos: false));
    // 通用组在折叠线下方，lazy list 需滚动才 build。
    await tester.drag(find.byType(Scrollable), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('后台运行'), findsOneWidget);
    expect(find.text('系统权限'), findsOneWidget);
  });
}

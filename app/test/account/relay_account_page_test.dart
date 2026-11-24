// The xcodex account's second-level page: the account's own card and the
// computers paired to it. Not logged in: the browser sign-in (no QR). Logging
// in: wait for the browser, cancel, copy the link. Logged in: account card +
// paired hosts (online/offline) + sign out. The API section is a placeholder.
//
//   flutter test test/account/relay_account_page_test.dart

import 'package:xagent/remote/relay/relay_backend.dart';
import 'package:xagent/state/hosts_state.dart';
import 'package:xagent/state/platform_state.dart';
import 'package:xagent/state/settings_state.dart';
import 'package:xagent/ui/account/relay_account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../shell/golden_harness.dart' show FakeSettings, goldenApp, usePhoneSurface;

class _FixedRelay extends RelayAccountController {
  _FixedRelay(this.initial);
  final RelayAccountState initial;

  @override
  Future<RelayAccountState> build() async => initial;
}

List<Override> _overrides({required RelayAccountState relay}) => [
  isIosProvider.overrideWithValue(true),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  relayAccountProvider.overrideWith(() => _FixedRelay(relay)),
];

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(home: const Scaffold(body: RelayAccountPage()), brightness: Brightness.light, overrides: overrides),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('not logged in: the browser sign-in, no QR', (tester) async {
    await _pump(tester, _overrides(relay: const RelayAccountState()));
    expect(find.text('使用 xcodex 账号登录'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.text('登录 xcodex 账号'), findsNothing);
  });

  testWidgets('logging in: wait, cancel, copy the link', (tester) async {
    await _pump(
      tester,
      _overrides(
        relay: RelayAccountState(
          available: true,
          server: 'agent.xcodex.vip',
          loggingIn: true,
          loginUrl: Uri.https('agent.xcodex.vip', 'login/x'),
        ),
      ),
    );
    expect(find.text('在浏览器里完成登录…'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('复制登录链接'), findsOneWidget);
  });

  testWidgets('signed in, no hosts: the account card and the empty state', (tester) async {
    await _pump(
      tester,
      _overrides(
        relay: const RelayAccountState(
          available: true,
          server: 'agent.xcodex.vip',
          user: RelayUser(id: 'u', displayName: 'tester', provider: 'password'),
          hosts: [],
        ),
      ),
    );
    expect(find.text('tester'), findsOneWidget);
    expect(find.text('还没有主机'), findsOneWidget);
  });

  testWidgets('signed in, two hosts: online and offline rows', (tester) async {
    await _pump(
      tester,
      _overrides(
        relay: const RelayAccountState(
          available: true,
          server: 'agent.xcodex.vip',
          user: RelayUser(id: 'u', displayName: 'tester', provider: 'password'),
          hosts: [
            RelayHost(id: 'h1', name: 'MacBook', online: true, platform: 'darwin', harnessVersion: '0.2.1-rc.2'),
            RelayHost(id: 'h2', name: 'Work PC', online: false, platform: 'windows'),
          ],
        ),
      ),
    );
    expect(find.text('MacBook'), findsOneWidget);
    expect(find.text('Work PC'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
  });
}

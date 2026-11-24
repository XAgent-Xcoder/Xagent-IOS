// The settings hub's overview card on a phone that signs in with an xcodex
// account: the card is the xcodex entry (not DeepSeek). Three states:
// signed out → 「登录 xcodex 账号」, logging in → 「正在登录 xcodex 账号」,
// signed in → 「已登录 · 主机名 · 在线」. Tapping opens RelayAccountPage.
//
//   flutter test test/settings/settings_overview_xcodex_test.dart

import 'package:xagent/remote/relay/relay_backend.dart';
import 'package:xagent/runtime/runtime_bridge.dart';
import 'package:xagent/runtime/runtime_state.dart';
import 'package:xagent/state/connection_state.dart';
import 'package:xagent/state/hosts_state.dart';
import 'package:xagent/state/platform_state.dart';
import 'package:xagent/state/settings_state.dart';
import 'package:xagent/ui/account/relay_account_page.dart';
import 'package:xagent/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../phone/support.dart' show FixedActiveHost, FixedHosts;
import '../shell/golden_harness.dart' show FakeRuntime, FakeSettings, goldenApp, usePhoneSurface;

const _missing = RuntimeStatus(phase: RuntimePhase.notInstalled, abi: 'arm64-v8a');

class _FixedRelay extends RelayAccountController {
  _FixedRelay(this.initial);
  final RelayAccountState initial;

  @override
  Future<RelayAccountState> build() async => initial;
}

List<Override> _overrides({required RelayAccountState relay, HostRef host = HostRef.local}) => [
  isIosProvider.overrideWithValue(true),
  localRuntimeProvider.overrideWith(() => FakeRuntime(LocalRuntimeState(loaded: true, status: _missing))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  activeHostProvider.overrideWith(() => FixedActiveHost(host)),
  hostsProvider.overrideWith(FixedHosts.new),
  hostLinkStatusProvider.overrideWith((ref, h) => Stream.value(HostLinkStatus(HostLinkPhase.connected))),
  relayAccountProvider.overrideWith(() => _FixedRelay(relay)),
];

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(home: const Scaffold(body: SettingsOverview()), brightness: Brightness.light, overrides: overrides),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('signed out: the card is the xcodex sign-in', (tester) async {
    await _pump(tester, _overrides(relay: const RelayAccountState()));
    expect(find.text('登录 xcodex 账号'), findsOneWidget);
    expect(find.text('登录 DeepSeek 账号'), findsNothing);
    expect(find.text('或填写 API Key'), findsNothing);
  });

  testWidgets('logging in: the card shows the wait', (tester) async {
    await _pump(
      tester,
      _overrides(
        relay: RelayAccountState(
          loggingIn: true,
          loginUrl: Uri.https('agent.xcodex.vip', 'login/x'),
        ),
      ),
    );
    expect(find.text('正在登录 xcodex 账号'), findsOneWidget);
  });

  testWidgets('signed in: the card is the host, and opens RelayAccountPage', (tester) async {
    await _pump(
      tester,
      _overrides(
        host: HostRef.relay('h1', name: 'MacBook'),
        relay: const RelayAccountState(
          user: RelayUser(id: 'u', displayName: 'tester', provider: 'password'),
          hosts: [RelayHost(id: 'h1', name: 'MacBook', online: true)],
        ),
      ),
    );
    expect(find.text('已登录 · MacBook · 已连接'), findsOneWidget);
    await tester.tap(find.text('tester'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(RelayAccountPage), findsOneWidget);
  });
}

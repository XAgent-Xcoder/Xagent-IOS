// The whole path: the settings overview card signs in with xcodex, tapping it
// opens the account's second-level page, which shows the browser sign-in.
// Regression lock over Task 1 (card → RelayAccountPage) and Task 2 (the page).
//
//   flutter test test/account/relay_account_page_flow_test.dart

import 'package:xagent/remote/relay/relay_backend.dart';
import 'package:xagent/state/hosts_state.dart';
import 'package:xagent/state/platform_state.dart';
import 'package:xagent/state/settings_state.dart';
import 'package:xagent/ui/account/relay_account_page.dart';
import 'package:xagent/ui/settings/settings_screen.dart';
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

List<Override> _overrides() => [
  isIosProvider.overrideWithValue(true),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
  relayAccountProvider.overrideWith(() => _FixedRelay(const RelayAccountState())),
];

Future<void> _pump(WidgetTester tester) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(home: const Scaffold(body: SettingsOverview()), brightness: Brightness.light, overrides: _overrides()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('overview card opens the account page, which shows the sign-in', (tester) async {
    await _pump(tester);
    expect(find.text('登录 xcodex 账号'), findsOneWidget);
    await tester.tap(find.text('登录 xcodex 账号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(RelayAccountPage), findsOneWidget);
    expect(find.text('使用 xcodex 账号登录'), findsOneWidget);
  });
}

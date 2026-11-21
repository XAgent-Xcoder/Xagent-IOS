// Task 4：iOS 搜索索引剔除本地专属页（入口行按 opens 目标页判、普通行按 page
// 判），全部功能目录剔除手机操控条目；远程共用页（引擎参数等）保留。
//
//   flutter test test/ios_search_catalog_filter_test.dart

import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/features/feature_catalog.dart';
import 'package:dsh_app/ui/settings/index/settings_pages.dart';
import 'package:dsh_app/ui/settings/search/settings_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'phone/support.dart' show FixedActiveHost, FixedHosts;
import 'shell/golden_harness.dart';

void main() {
  test('visibleSettingSpots 入口行按 opens 判、普通行按 page 判', () {
    final visible = visibleSettingSpots(
      SettingsIndex.spots,
      engineBlocked: true,
      phoneBlocked: true,
    );
    // 本机引擎入口行：page=hub、opens=engine——只按 page 判会漏，必须按 opens 剔掉。
    expect(visible.any((s) => s.opens == SettingsPageId.engine), isFalse);
    expect(visible.any((s) => s.page == SettingsPageId.engine), isFalse);
    expect(visible.any((s) => s.opens == SettingsPageId.phone || s.page == SettingsPageId.phone), isFalse);
    expect(visible.any((s) => s.page == SettingsPageId.phoneAppRules), isFalse);
    expect(visible.any((s) => s.opens == SettingsPageId.background || s.page == SettingsPageId.background), isFalse);
    expect(visible.any((s) => s.opens == SettingsPageId.systemAccess || s.page == SettingsPageId.systemAccess), isFalse);
    // 远程共用保留。
    expect(visible.any((s) => s.opens == SettingsPageId.engineParams || s.page == SettingsPageId.engineParams), isTrue);
    expect(visible.any((s) => s.opens == SettingsPageId.remote || s.page == SettingsPageId.remote), isTrue);
    // Android 能力不剔任何行。
    expect(
      visibleSettingSpots(SettingsIndex.spots, engineBlocked: false, phoneBlocked: false).length,
      SettingsIndex.spots.length,
    );
  });

  test('featureCatalogBlockedIds 只含手机操控条目', () {
    // 目录里构造本地专属页面的条目（web 条目走当前主机的 DSH Web，远程有效，不剔）。
    expect(featureCatalogBlockedIds, contains('phone'));
    expect(featureCatalogBlockedIds, isNot(contains('web')));
    expect(featureCatalogBlockedIds, isNot(contains('remote')));
  });

  List<Override> _overrides(bool isIos) => [
    isIosProvider.overrideWithValue(isIos),
    settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
    activeHostProvider.overrideWith(() => FixedActiveHost(const HostRef.ssh('lab'))),
    hostsProvider.overrideWith(FixedHosts.new),
    networkKicksProvider.overrideWithValue(const Stream.empty()),
  ];

  Future<void> _search(WidgetTester tester, bool isIos, String query) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      goldenApp(home: const SettingsSearchPage(), brightness: Brightness.light, overrides: _overrides(isIos)),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('iOS 搜索"引擎"不出本机引擎结果，引擎参数保留', (tester) async {
    await _search(tester, true, '引擎');
    expect(find.text('本机引擎'), findsNothing);
    expect(find.textContaining('引擎参数'), findsWidgets);
  });

  testWidgets('Android 搜索"引擎"两者都在（对照）', (tester) async {
    await _search(tester, false, '引擎');
    expect(find.textContaining('本机引擎'), findsWidgets);
    expect(find.textContaining('引擎参数'), findsWidgets);
  });
}

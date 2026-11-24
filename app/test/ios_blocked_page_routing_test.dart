// iOS 访问层门禁：被禁设置页在任何解析路径下都不可达。
// 能力以两个 bool 传入（settingsPage 是无 ref 纯函数，全链共用同一判定）。
//
//   flutter test test/ios_blocked_page_routing_test.dart

import 'package:xagent/links/page_links.dart';
import 'package:xagent/ui/settings/blocked_page.dart';
import 'package:xagent/ui/settings/index/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell/golden_harness.dart';

void main() {
  test('iOS 被禁 id 集合完整且不误伤共用页', () {
    for (final id in [...localEngineOnlyPageIds, ...phoneControlPageIds]) {
      expect(settingsPageBlocked(id, engineBlocked: true, phoneBlocked: true), isTrue, reason: '$id 应被拦');
    }
    for (final id in [
      SettingsPageId.engineParams,
      SettingsPageId.models,
      SettingsPageId.remote,
      SettingsPageId.plugins,
      SettingsPageId.diagnostics,
      SettingsPageId.permission,
    ]) {
      expect(settingsPageBlocked(id, engineBlocked: true, phoneBlocked: true), isFalse, reason: '$id 是远程共用能力');
    }
  });

  test('能力开关各自独立：只拦引擎不影响手机操控页，反之亦然', () {
    expect(settingsPageBlocked(SettingsPageId.engine, engineBlocked: true, phoneBlocked: false), isTrue);
    expect(settingsPageBlocked(SettingsPageId.phone, engineBlocked: true, phoneBlocked: false), isFalse);
    expect(settingsPageBlocked(SettingsPageId.phoneDnd, engineBlocked: false, phoneBlocked: true), isTrue);
    expect(settingsPageBlocked(SettingsPageId.background, engineBlocked: false, phoneBlocked: true), isFalse);
  });

  test('Android 能力不拦任何页', () {
    for (final id in [...localEngineOnlyPageIds, ...phoneControlPageIds]) {
      expect(settingsPageBlocked(id, engineBlocked: false, phoneBlocked: false), isFalse);
    }
  });

  testWidgets('iOS settingsPage(engine) 返回 BlockedFeaturePage（真文案）', (tester) async {
    final page = settingsPage(SettingsPageId.engine, engineBlocked: true, phoneBlocked: true);
    expect(page, isA<BlockedFeaturePage>());
    usePhoneSurface(tester);
    await tester.pumpWidget(goldenApp(home: page, brightness: Brightness.light));
    await tester.pump();
    expect(find.text('此功能在 iOS 上不可用'), findsOneWidget);
  });

  testWidgets('Android settingsPage(engine) 返回真引擎页', (tester) async {
    final page = settingsPage(SettingsPageId.engine, engineBlocked: false, phoneBlocked: false);
    expect(page, isNot(isA<BlockedFeaturePage>()));
  });

  test('iOS pageForId 对被禁 id 返回 null（走 LinkRouter 既有兜底）', () {
    expect(pageForId('engine', null, engineBlocked: true, phoneBlocked: true), isNull);
    expect(pageForId('phone', null, engineBlocked: true, phoneBlocked: true), isNull);
    // 共用能力不受影响（link id 是 engine-settings，非枚举名）
    expect(pageForId('engine-settings', null, engineBlocked: true, phoneBlocked: true), isNotNull);
    // Android 照常
    expect(pageForId('engine', null, engineBlocked: false, phoneBlocked: false), isNotNull);
  });
}

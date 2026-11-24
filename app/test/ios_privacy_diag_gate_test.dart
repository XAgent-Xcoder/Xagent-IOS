import 'dart:async';
// Task 5：iOS 隐私页无"本机文字识别"区块（跳手机操控）、诊断输入法区块无
// 权限跳转行；openLocalInstall 在 iOS 明确失败（local_unsupported），不静默。
//
//   flutter test test/ios_privacy_diag_gate_test.dart

import 'package:xagent/diagnostics/system_ime_evidence.dart';
import 'package:xagent/runtime/runtime_bridge.dart';
import 'package:xagent/runtime/runtime_state.dart';
import 'package:xagent/state/platform_state.dart';
import 'package:xagent/state/settings_state.dart';
import 'package:xagent/ui/onboarding/local_install.dart';
import 'package:xagent/ui/settings/diagnostics_page.dart';
import 'package:xagent/ui/settings/privacy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell/golden_harness.dart';
import 'onboarding/local_optional_support.dart' show footprint, roomyPhone;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> _pump(WidgetTester tester, Widget page, bool isIos) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      goldenApp(home: page, brightness: Brightness.light, overrides: [isIosProvider.overrideWithValue(isIos)]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('iOS 隐私页无本机文字识别区块', (tester) async {
    await _pump(tester, const Scaffold(body: PrivacyPage()), true);
    expect(find.textContaining('本机文字识别'), findsNothing);
    // 远程共用区块保留。
    expect(find.textContaining('分享'), findsWidgets);
  });

  testWidgets('Android 隐私页有本机文字识别区块（对照）', (tester) async {
    await _pump(tester, const Scaffold(body: PrivacyPage()), false);
    expect(find.textContaining('本机文字识别'), findsWidgets);
  });

  Future<void> _collectIme(WidgetTester tester, bool isIos) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dsh/diagnostics'),
      (call) async => call.method == 'collectSystemIme'
          ? <String, Object?>{'code': 'unavailable', 'source': 'privilegedIme', 'ok': false, 'capturedAt': now, 'events': <Object?>[]}
          : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dsh/diagnostics'),
      null,
    ));
    await _pump(tester, const Scaffold(body: SingleChildScrollView(child: SystemImeDiagnosticsSection())), isIos);
    await tester.tap(find.text('采集本次日志'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('iOS 诊断输入法区块无权限跳转行（采集不可用后）', (tester) async {
    await _collectIme(tester, true);
    expect(find.textContaining('手机操控权限设置'), findsNothing);
    // 采集与状态行本身保留（通用诊断不杀）。
    expect(find.text('采集本次日志'), findsOneWidget);
  });

  testWidgets('Android 诊断输入法区块有权限跳转行（对照）', (tester) async {
    await _collectIme(tester, false);
    expect(find.textContaining('手机操控权限设置'), findsOneWidget);
  });

  Future<void> _pumpHome(WidgetTester tester, bool isIos) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const Scaffold(body: SizedBox()),
        brightness: Brightness.light,
        overrides: [
          isIosProvider.overrideWithValue(isIos),
          localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.notInstalled)))),
          settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
          footprint(roomyPhone),
        ],
      ),
    );
    await tester.pump();
  }

  // openLocalInstall 返回 Navigator.push 的 future（页面 pop 才完成）：
  // 测试不能 await 它，否则永远挂住。失败经 catchError 收进 err。
  testWidgets('iOS openLocalInstall 明确失败（local_unsupported），不推安装页', (tester) async {
    await _pumpHome(tester, true);
    final ctx = tester.element(find.byType(Scaffold));
    Object? err;
    unawaited(openLocalInstall(ctx).catchError((Object e) => err = e));
    await tester.pump();
    expect(err, isA<PlatformException>());
    expect((err as PlatformException).code, 'local_unsupported');
    expect(find.byType(LocalInstallPage), findsNothing);
  });

  testWidgets('Android openLocalInstall 推安装页（对照）', (tester) async {
    await _pumpHome(tester, false);
    final ctx = tester.element(find.byType(Scaffold));
    unawaited(openLocalInstall(ctx));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LocalInstallPage), findsOneWidget);
  });

  test('SystemImeEvidence 形状常量（防 mock 漂移）', () {
    expect(SystemImeEvidence.codes, contains('unavailable'));
  });
}

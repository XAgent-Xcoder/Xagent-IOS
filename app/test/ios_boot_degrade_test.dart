// iOS 远程客户端不跑本地引擎（PRoot）。RootGate 的自动启动在 Android 上会把
// 已安装的引擎拉起来；iOS 上这条路径必须不触发，否则冷启动就去调本地引擎
// 通道。用 RecordingRuntime 记录 start 调用：iOS 下为空，Android 下为 'start'。
//
//   flutter test test/ios_boot_degrade_test.dart

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'safe_mode/support.dart';
import 'shell/golden_harness.dart';

class _Logs extends LocalRuntimeLogsController {
  @override
  List<String> build() => const [];
}

Future<RecordingRuntime> _pumpRootGate(
  WidgetTester tester, {
  required bool isIos,
  bool autoStart = true,
}) async {
  final runtime = RecordingRuntime(
    const LocalRuntimeState(
      loaded: true,
      status: RuntimeStatus(phase: RuntimePhase.installed, bundledVersion: 'r1', installedVersion: 'r1'),
    ),
  );
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(
      home: const RootGate(home: Scaffold(body: Text('home'))),
      brightness: Brightness.light,
      overrides: [
        isIosProvider.overrideWithValue(isIos),
        localRuntimeProvider.overrideWith(() => runtime),
        localRuntimeLogsProvider.overrideWith(() => _Logs()),
        settingsProvider.overrideWith(() => FakeSettings(AppSettings(loaded: true, apiKey: 'key', autoStartLocal: autoStart))),
      ],
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return runtime;
}

void main() {
  testWidgets('iOS 冷启动不自动拉起本地引擎', (tester) async {
    final runtime = await _pumpRootGate(tester, isIos: true);
    // 运行时是 installed、autoStartLocal 为 true，但 iOS 上不该 start。
    expect(runtime.starts, isEmpty);
  });

  testWidgets('Android 冷启动仍自动拉起本地引擎', (tester) async {
    final runtime = await _pumpRootGate(tester, isIos: false);
    expect(runtime.starts, ['start']);
  });
}

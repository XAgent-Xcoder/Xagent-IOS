// Task 6：iOS 上本机引擎的连接建立必须被能力门禁短路——running + 有效
// baseUrl/token 的场景下 localClientConnector 调用数为 0（外部评审补漏：
// notInstalled 场景本来就返回 null，证明不了门禁）。Android 对照：connector
// 被调用且连接建立。
//
//   flutter test test/ios_state_layer_no_local_calls_test.dart

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/platform_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote/support/ready_mux.dart';

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => const LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus(
      phase: RuntimePhase.running,
      abi: 'arm64-v8a',
      bundledVersion: 'r1',
      installedVersion: 'r1',
      baseUrl: 'http://127.0.0.1:3080',
      token: 't',
    ),
  );
}

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

class _LocalClient extends DshClient {
  _LocalClient() : super(DshConnection(Uri.parse('http://127.0.0.1:9')));
  final _mux = ReadyMux();
  @override
  DshMux get mux => _mux;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer _container({required bool isIos, required void Function() connector}) => ProviderContainer(
    overrides: [
      isIosProvider.overrideWithValue(isIos),
      settingsProvider.overrideWith(_Settings.new),
      localRuntimeProvider.overrideWith(_Runtime.new),
      networkKicksProvider.overrideWithValue(const Stream.empty()),
      localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async {
        connector.call();
        return _LocalClient();
      }),
    ],
  );

  test('iOS：running+有效地址，connector 调用数为 0，连接为 null', () async {
    var calls = 0;
    final c = _container(isIos: true, connector: () => calls++);
    addTearDown(c.dispose);
    final conn = await c.read(localConnectionProvider.future);
    expect(calls, 0);
    expect(conn, isNull);
  });

  test('Android 对照：同场景 connector 被调用且连接建立', () async {
    AppLocale.use(AppLocale.zhCN);
    var calls = 0;
    final c = _container(isIos: false, connector: () => calls++);
    addTearDown(c.dispose);
    final conn = await c.read(localConnectionProvider.future);
    expect(calls, greaterThanOrEqualTo(1));
    expect(conn, isNotNull);
  });
}

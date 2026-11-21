import 'dart:async';

import 'package:dsh_app/remote/orca/orca_host_config.dart';
import 'package:dsh_app/remote/secret_store.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/orca_connection_state.dart';
import 'package:dsh_app/state/orca_hosts_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orca_client/orca_client.dart';

/// A transport that records every RPC and returns canned results, so the
/// connection provider can be exercised without a live host.
class _RecordingTransport implements OrcaRpcTransport {
  final sent = <String>[];
  bool closed = false;

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 30)}) async {
    sent.add(method);
    return {'ok': true, 'value': {}};
  }

  @override
  Stream<Map<String, dynamic>> subscribe(String sessionId, {Map<String, dynamic>? cursor}) =>
      const Stream.empty();

  @override
  Future<void> close() async => closed = true;
}

/// A fixed OrcaHostsController so tests don't touch SharedPreferences.
class _FixedOrcaHosts extends OrcaHostsController {
  _FixedOrcaHosts(this._hosts);
  final OrcaHostsState _hosts;
  @override
  OrcaHostsState build() => _hosts;
}

OrcaHostConfig _host(String endpoint) =>
    OrcaHostConfig(id: 'orca-1', name: 'host', endpoint: endpoint);

void main() {
  test('an unknown orca host yields null (no host saved under this id)', () async {
    final container = ProviderContainer(overrides: [
      orcaHostsProvider.overrideWith(() => _FixedOrcaHosts(
        OrcaHostsState(orca: [_host('ws://127.0.0.1:6769')], loaded: true),
      )),
    ]);
    addTearDown(container.dispose);
    // Wait for the notifier's build to settle, then read the value.
    await container.read(orcaBackendProvider(HostRef.orca('missing')).notifier).future;
    final value = container.read(orcaBackendProvider(HostRef.orca('missing')));
    expect(value, isA<AsyncData<MobileChatBackend?>>());
    expect(value.value, isNull);
  });

  test('a missing pairing code fails loudly without opening a connection', () async {
    final connected = _RecordingTransport();
    final connectorCalls = <Object?>[];
    final container = ProviderContainer(overrides: [
      orcaHostsProvider.overrideWith(() => _FixedOrcaHosts(
        OrcaHostsState(orca: [_host('ws://127.0.0.1:6769')], loaded: true),
      )),
      orcaConnectorProvider.overrideWith(
        (ref) => (endpoint, code) async {
          connectorCalls.add(endpoint);
          return connected;
        },
      ),
    ]);
    addTearDown(container.dispose);
    // The build fails (no pairing code); its future carries the error, so
    // swallow it here and assert on the published AsyncError instead.
    await container
        .read(orcaBackendProvider(HostRef.orca('orca-1')).notifier)
        .future
        .catchError((Object _) => null);
    final value = container.read(orcaBackendProvider(HostRef.orca('orca-1')));
    expect(value, isA<AsyncError<MobileChatBackend?>>());
    // Not pretending success: no transport was opened.
    expect(connectorCalls, isEmpty);
  });

  test('saved endpoint + pairing code produce a working backend', () async {
    final transport = _RecordingTransport();
    final container = ProviderContainer(overrides: [
      orcaHostsProvider.overrideWith(() => _FixedOrcaHosts(
        OrcaHostsState(orca: [_host('ws://127.0.0.1:6769')], loaded: true),
      )),
      secretStoreProvider.overrideWithValue(
        MemorySecretStore({OrcaSecrets.pairingCodeKey('orca-1'): 'offer'}),
      ),
      orcaConnectorProvider.overrideWith(
        (ref) => (endpoint, code) async {
          expect(endpoint, Uri.parse('ws://127.0.0.1:6769'));
          expect(code, 'offer');
          return transport;
        },
      ),
    ]);
    addTearDown(container.dispose);
    // Wait for the notifier's build to settle, then read the value.
    await container.read(orcaBackendProvider(HostRef.orca('orca-1')).notifier).future;
    final value = container.read(orcaBackendProvider(HostRef.orca('orca-1')));
    expect(value.value, isA<OrcaMobileBackend>());
    expect(value.value!.capabilities.supportsTerminal, isFalse);
  });
}

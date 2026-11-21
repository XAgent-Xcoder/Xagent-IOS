import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orca_client/orca_client.dart';

import '../remote/orca/orca_host_config.dart';
import '../remote/secret_store.dart';
import 'hosts_state.dart';
import 'orca_hosts_state.dart';

/// Builds the authenticated transport for one orca host. [endpoint] is the
/// host's WebSocket URI; [pairingCode] is the host's offer (a base64 blob).
/// Tests swap this in with a fake [OrcaRpcTransport] so a backend can be
/// exercised without a live host.
typedef OrcaConnector = Future<OrcaRpcTransport> Function(
  Uri endpoint,
  String pairingCode,
);

/// The live connector: legacy pairing + E2EE handshake, then a request/
/// subscribe RPC channel. The [LegacyOrcaClient] *is* the transport (it
/// implements [OrcaRpcTransport]).
final orcaConnectorProvider = Provider<OrcaConnector>(
  (ref) => (endpoint, code) => LegacyOrcaClient.connect(endpoint, code),
);

/// The [MobileChatBackend] for one orca host: its pairing code from the
/// [SecretStore], its endpoint from the saved [OrcaHostConfig]. Unknown hosts
/// or a missing pairing code yield `AsyncData(null)` / `AsyncError` — never a
/// half-open connection presented as success.
final orcaBackendProvider = AsyncNotifierProvider.family<OrcaBackendController, MobileChatBackend?, HostRef>(
  OrcaBackendController.new,
);

class OrcaBackendController extends AsyncNotifier<MobileChatBackend?> {
  OrcaBackendController(this.host);

  final HostRef host;

  @override
  Future<MobileChatBackend?> build() async {
    final hosts = ref.read(orcaHostsProvider);
    final config = hosts.orcaById(host.id);
    if (config == null || config.endpoint.trim().isEmpty) return null;
    final code = await ref.read(orcaHostsProvider.notifier).loadPairingCode(host.id);
    if (code == null || code.trim().isEmpty) {
      throw StateError('Orca host ${host.id} has no pairing code saved');
    }
    final transport =
        await ref.read(orcaConnectorProvider)(Uri.parse(config.endpoint), code.trim());
    if (!ref.mounted) {
      await transport.close();
      return null;
    }
    final backend = OrcaMobileBackend(transport);
    ref.onDispose(() => unawaited(backend.close()));
    return backend;
  }
}

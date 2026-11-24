import 'package:xagent/state/connection_state.dart';
import 'package:xagent/state/hosts_state.dart';
import 'package:xagent/state/managed_agents_state.dart';
import 'package:xagent/state/read_list_identity.dart';
import 'package:xagent/state/sessions_state.dart';
import 'package:xagent/state/workspaces_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workspace/support.dart';

const _workspace = Workspace(workspaceId: 'ws', path: '/project', title: 'Project', sessionIds: []);
const _agent = ManagedAgentDefinition(
  id: 'codex',
  name: 'Codex',
  available: true,
  capabilities: ManagedAgentCapabilities({}),
);
final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

class _Host extends ActiveHostController {
  @override
  HostRef build() => const HostRef.relay('computer');
}

class _Workspaces extends WorkspacesController {
  @override
  WorkspacesState build() => const WorkspacesState(status: WorkspacesStatus.ready, workspaces: [_workspace]);
}

/// Records the operationId of every `managedAgent/create`; honours a failure.
class _ManagedHost extends FakeWorkspaceHost {
  final operationIds = <String>[];
  bool fail = false;

  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async {
    if (endpoint == 'managedAgent/create') {
      final request = (args['request'] as Map).cast<String, Object?>();
      operationIds.add(request['operationId']! as String);
      if (fail) throw const DshHttpException(400, 'response lost');
      return const RpcOk({'sessionId': 'managed-new'});
    }
    return super.call(endpoint, args, timeout: timeout);
  }
}

void main() {
  test('a failed creation throws before any native session; a new agent mints a new operation id', () async {
    final host = _ManagedHost();
    final conn = HostConnection(client: DshClient.withCarrier(host), isLocal: false, kind: HostKind.relay);
    final container = ProviderContainer(
      overrides: [
        activeHostProvider.overrideWith(_Host.new),
        readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
        readListLiveConnectionProvider.overrideWithValue(conn),
        workspacesProvider.overrideWith(_Workspaces.new),
        selectedWorkspaceProvider.overrideWithValue(_workspace),
        managedAgentsProvider.overrideWith((ref) async => const [_agent]),
      ],
    );
    addTearDown(container.dispose);
    container.read(pendingManagedAgentProvider.notifier).select(_agent);

    // A failed prepare throws and records a valid operation id; no native session.
    host.fail = true;
    await expectLater(container.read(managedDraftSessionProvider.future), throwsException);
    final failedId = host.operationIds.single;
    expect(failedId, matches(_uuid));
    expect(host.calls.every((call) => call.$1 != 'session/create'), isTrue, reason: 'no native session/create on a managed draft');

    // A different agent gets a fresh operation id.
    host.fail = false;
    container.read(pendingManagedAgentProvider.notifier).select(const ManagedAgentDefinition(
      id: 'claude',
      name: 'Claude Code',
      available: true,
      capabilities: ManagedAgentCapabilities({}),
    ));
    container.invalidate(managedDraftSessionProvider);
    final sessionId = await container.read(managedDraftSessionProvider.future);
    expect(sessionId, 'managed-new');
    expect(host.operationIds.last, isNot(failedId), reason: 'a new agent choice gets a fresh operation id');
  });

  test('workspace and host are required before a draft can be created', () async {
    final conn = HostConnection(
      client: DshClient.withCarrier(FakeWorkspaceHost()),
      isLocal: false,
      kind: HostKind.relay,
    );
    ProviderContainer forCase(Map<Provider<Object?>, Object?> overrides) {
      final container = ProviderContainer(
        overrides: [
          activeHostProvider.overrideWith(_Host.new),
          readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
          readListLiveConnectionProvider.overrideWithValue(conn),
          recentWorkspaceForNewChatProvider.overrideWithValue(null),
          ...overrides.entries.map((e) => e.key.overrideWithValue(e.value)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // No selected workspace and no recent one: the provider fails before any RPC.
    final noWorkspace = forCase({selectedWorkspaceProvider: null});
    noWorkspace.read(pendingManagedAgentProvider.notifier).select(_agent);
    await expectLater(noWorkspace.read(managedDraftSessionProvider.future), throwsA(isA<DshClosedException>()));

    // A pending agent but no live connection: also fails before any RPC.
    final noConnection = ProviderContainer(
      overrides: [
        activeHostProvider.overrideWith(_Host.new),
        readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
        readListLiveConnectionProvider.overrideWithValue(null),
        selectedWorkspaceProvider.overrideWithValue(_workspace),
      ],
    );
    addTearDown(noConnection.dispose);
    noConnection.read(pendingManagedAgentProvider.notifier).select(_agent);
    await expectLater(noConnection.read(managedDraftSessionProvider.future), throwsA(isA<DshClosedException>()));
  });
}

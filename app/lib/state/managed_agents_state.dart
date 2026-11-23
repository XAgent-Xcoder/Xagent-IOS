import 'dart:math';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hosts_state.dart';
import 'drawer_view_state.dart';
import 'chat_state.dart';
import 'sessions_state.dart';
import 'read_list_identity.dart';
import 'workspaces_state.dart';

/// A new-chat choice belongs to its account/Host, and survives reconnects.
final pendingManagedAgentProvider = NotifierProvider<PendingManagedAgent, ManagedAgentDefinition?>(
  PendingManagedAgent.new,
);

class PendingManagedAgent extends Notifier<ManagedAgentDefinition?> {
  @override
  ManagedAgentDefinition? build() {
    ref.watch(activeHostProvider);
    ref.watch(readListIdentityProvider);
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous != null && next == null) state = null;
    });
    return null;
  }

  void select(ManagedAgentDefinition? agent) => state = agent;
}

final managedAgentsProvider = FutureProvider<List<ManagedAgentDefinition>>((ref) async {
  final conn = ref.watch(readListLiveConnectionProvider);
  ref.watch(readListIdentityProvider);
  // These RPC extensions travel through the authenticated plugin tunnel.
  if (conn == null || ref.watch(activeHostProvider).kind != HostKind.relay) return const [];
  try {
    return await conn.client.listManagedAgents();
  } on DshRemoteException catch (error) {
    if (const [
      'METHOD_NOT_ALLOWED',
      'METHOD_NOT_FOUND',
      'gateway/method-not-found',
      'gateway/not-found',
    ].contains(error.code)) {
      return const [];
    }
    rethrow;
  }
});

final managedSessionProvider = Provider.family<SessionProjections?, String?>((ref, id) {
  if (id == null) return null;
  for (final session in ref.watch(sessionsProvider).value ?? const <SessionSummary>[]) {
    if (session.sessionId == id && session.isManagedAgent) return session.projections;
  }
  // A directly resumed chat can receive its snapshot before session/list.
  // Limit the fallback to the selected chat: do not activate background sessions.
  if (ref.watch(currentSessionProvider) == id) {
    ref.watch(chatProvider(id));
    final projections = ref.read(chatProvider(id).notifier).projections;
    if (projections.isManagedAgent) return projections;
  }
  return null;
});

/// Retain the create identity on an ambiguous response, including retry after
/// reconnect. Scope includes the account/Host display identity; no credentials.
final managedCreationProvider = Provider((ref) => ManagedSessionCreation());

class ManagedSessionCreation {
  final operations = ManagedCreationOperations();
  Future<String> create(
    WidgetRef ref,
    String workspaceId,
    String agentId, {
    String? folderId,
    bool navigate = true,
    required bool Function() isCurrent,
  }) async {
    final conn = ref.read(readListLiveConnectionProvider);
    final owner = ref.read(readListIdentityProvider);
    final host = ref.read(activeHostProvider);
    if (conn == null || owner == null || host.kind != HostKind.relay) {
      throw const DshClosedException('Host unavailable');
    }
    final generation = conn.client.mux.generation;
    void check() {
      if (!isCurrent() ||
          ref.read(readListIdentityProvider) != owner ||
          ref.read(activeHostProvider) != host ||
          !identical(ref.read(readListLiveConnectionProvider), conn) ||
          !identical(conn.client.mux.generation, generation) ||
          !ref.read(workspacesProvider).ready ||
          ref.read(workspacesProvider).byId(workspaceId) == null) {
        throw const DshClosedException('Session creation context changed');
      }
    }

    check();
    return operations.run(
      owner.digest,
      workspaceId,
      agentId,
      check: check,
      action: (operationId) async {
        final created = await conn.client.createManagedSession(
          workspaceId: workspaceId,
          agentId: agentId,
          operationId: operationId,
        );
        check();
        await ref.read(sessionsProvider.notifier).refresh();
        check();
        if (folderId != null) {
          await ref
              .read(drawerViewProvider.notifier)
              .moveSessions(
                [created.sessionId],
                folderId,
                isCurrent: () {
                  check();
                  return true;
                },
              );
          check();
        }
        if (navigate) ref.read(currentSessionProvider.notifier).select(created.sessionId);
        return created.sessionId;
      },
    );
  }
}

/// Retains uncertain delivery IDs within an account/Host/workspace/Agent scope.
/// Explicit retry reuses the ID; success clears it for the next new session.
class ManagedCreationOperations {
  final _pending = <(String, String, String), String>{};
  final _busy = <(String, String, String)>{};
  Future<String> run(
    String owner,
    String workspaceId,
    String agentId, {
    required void Function() check,
    required Future<String> Function(String operationId) action,
  }) async {
    check();
    final key = (owner, workspaceId, agentId);
    if (!_busy.add(key)) throw const DshClosedException('Session creation is already pending');
    final operationId = _pending.putIfAbsent(key, _operationId);
    try {
      final result = await action(operationId);
      check();
      _pending.remove(key);
      return result;
    } finally {
      _busy.remove(key);
    }
  }
}

String _operationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

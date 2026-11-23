import 'dart:math';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hosts_state.dart';
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

/// A draft keeps its operation ID through a reconnect or an explicit retry.
final _draftOperationProvider = Provider.autoDispose((ref) {
  ref.watch(readListIdentityProvider);
  ref.watch(activeHostProvider);
  ref.watch(pendingManagedAgentProvider);
  ref.watch(draftWorkspaceIdProvider);
  return _operationId();
});

final draftWorkspaceIdProvider = Provider<String?>(
  (ref) =>
      ref.watch(selectedWorkspaceIdProvider) ??
      ref.watch(recentWorkspaceForNewChatProvider.select((workspace) => workspace?.workspaceId)),
);

/// Preparing a managed chat does not navigate away from the new-chat composer.
final managedDraftSessionProvider = FutureProvider.autoDispose<String>((ref) async {
  final operationId = ref.watch(_draftOperationProvider);
  final workspaceId = ref.watch(draftWorkspaceIdProvider);
  final agent = ref.watch(pendingManagedAgentProvider);
  final conn = ref.watch(readListLiveConnectionProvider);
  if (workspaceId == null) throw const DshClosedException('Workspace unavailable');
  if (agent == null || conn == null || ref.watch(readListIdentityProvider) == null) {
    throw const DshClosedException('Host unavailable');
  }
  final created = await conn.client.createManagedSession(
    workspaceId: workspaceId,
    agentId: agent.id,
    operationId: operationId,
  );
  return created.sessionId;
}, retry: (_, _) => null);

class ManagedDraftModel extends Notifier<ModelSelection?> {
  @override
  ModelSelection? build() {
    ref.watch(_draftOperationProvider);
    return null;
  }

  void select(ModelSelection selection) => state = selection;
}

final managedDraftModelProvider = NotifierProvider.autoDispose<ManagedDraftModel, ModelSelection?>(
  ManagedDraftModel.new,
);

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

String _operationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

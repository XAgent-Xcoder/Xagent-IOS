import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/managed_agents_state.dart';
import '../../state/hosts_state.dart';
import '../../state/read_list_identity.dart';
import '../../state/sessions_state.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import 'managed_agent_logo.dart';

/// New-chat entry points return to the shared composer, including folder shortcuts.
Future<void> showNewAgentSession(
  BuildContext context,
  WidgetRef ref,
  VoidCallback newChat,
  VoidCallback closeDrawer, {
  String? folderId,
}) async {
  if (ref.read(activeHostProvider).kind != HostKind.relay) {
    newChat();
    return;
  }
  ref.read(pendingManagedAgentProvider.notifier).select(null);
  ref.read(currentSessionProvider.notifier).select(null);
  if (folderId != null) ref.read(pendingSessionFolderProvider.notifier).select(folderId);
  closeDrawer();
}

Future<void> showAgentPicker(BuildContext context, WidgetRef ref) async {
  final owner = ref.read(readListIdentityProvider);
  await showAppSheet<void>(
    context,
    builder: (context) => Consumer(
      builder: (context, sheetRef, _) {
        final agents = sheetRef.watch(managedAgentsProvider);
        final selected = sheetRef.watch(pendingManagedAgentProvider);
        final connected = sheetRef.watch(readListLiveConnectionProvider) != null;
        final colors = Theme.of(context).colorScheme;
        Widget option(ManagedAgentDefinition? agent) {
          final active = selected?.id == agent?.id;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Material(
              color: active ? colors.secondaryContainer : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: agent == null
                        ? const Icon(Icons.terminal_rounded)
                        : ManagedAgentLogo(agentId: agent.id, size: 24),
                  ),
                ),
                title: Text(agent?.name ?? 'DSH'),
                trailing: active ? Icon(Icons.check_rounded, color: colors.primary) : null,
                selected: active,
                enabled: agent == null || (connected && agent.available),
                onTap: () {
                  if (sheetRef.read(readListIdentityProvider) == owner &&
                      sheetRef.read(currentSessionProvider) == null) {
                    sheetRef.read(pendingManagedAgentProvider.notifier).select(agent);
                  }
                  Navigator.pop(context);
                },
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitleBar(context.l10n.managedChooseAgent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      option(null),
                      if (agents.isLoading) const LinearProgressIndicator(),
                      if (!connected)
                        Text(context.l10n.managedConnectHost)
                      else if (agents.hasError)
                        TextButton(
                          onPressed: () => sheetRef.invalidate(managedAgentsProvider),
                          child: Text(context.l10n.managedDiscoveryRetry),
                        )
                      else if (!agents.isLoading) ...[
                        for (final agent in agents.value ?? const <ManagedAgentDefinition>[]) option(agent),
                        if (agents.value?.isEmpty ?? true) Text(context.l10n.managedUnavailable),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

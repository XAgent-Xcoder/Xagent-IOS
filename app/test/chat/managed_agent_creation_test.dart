import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/managed_agents_state.dart';
import 'package:dsh_app/state/read_list_identity.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/ui/chat/managed_agent_picker.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workspace/support.dart';
import 'support/harness.dart';

const agents = [
  ManagedAgentDefinition(
    id: 'claude',
    name: 'Claude Code',
    available: true,
    capabilities: ManagedAgentCapabilities({}),
  ),
  ManagedAgentDefinition(id: 'codex', name: 'Codex', available: true, capabilities: ManagedAgentCapabilities({})),
];

class _Host extends ActiveHostController {
  @override
  HostRef build() => const HostRef.relay('computer');
}

class _Current extends CurrentSessionController {
  @override
  String? build() => null;
  @override
  void select(String? id) => state = id;
}

/// A relay connection the picker reads; [connected] nulls it for the offline case.
Future<WidgetRef> open(WidgetTester tester, {required bool connected}) async {
  final connection = HostConnection(
    client: DshClient.withCarrier(FakeWorkspaceHost()),
    isLocal: false,
    kind: HostKind.relay,
  );
  late WidgetRef ref;
  await tester.pumpWidget(
    testApp(
      Consumer(
        builder: (context, value, _) {
          ref = value;
          return Scaffold(
            body: Row(
              children: [
                TextButton(onPressed: () => showAgentPicker(context, ref), child: const Text('pick')),
                TextButton(
                  onPressed: () => showNewAgentSession(context, ref, () {}, () {}, folderId: 'folder'),
                  child: const Text('new-folder'),
                ),
                TextButton(
                  onPressed: () => showNewAgentSession(context, ref, () {}, () {}),
                  child: const Text('new'),
                ),
              ],
            ),
          );
        },
      ),
      overrides: [
        activeHostProvider.overrideWith(_Host.new),
        readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
        readListLiveConnectionProvider.overrideWithValue(connected ? connection : null),
        managedAgentsProvider.overrideWith((ref) async => agents),
        currentSessionProvider.overrideWith(_Current.new),
      ],
    ),
  );
  return ref;
}

void main() {
  testWidgets('picker lists DSH and the registered managed agents', (tester) async {
    await open(tester, connected: true);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('选择 Agent'), findsOneWidget);
    expect(find.text('DSH'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
  });
  testWidgets('picking a managed agent selects it; DSH clears it', (tester) async {
    final ref = await open(tester, connected: true);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(ref.read(pendingManagedAgentProvider)?.id, 'codex');
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DSH'));
    await tester.pumpAndSettle();
    expect(ref.read(pendingManagedAgentProvider), isNull);
  });
  testWidgets('offline picker shows the connect hint, DSH only', (tester) async {
    await open(tester, connected: false);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('请先连接电脑，再创建 Claude Code 或 Codex 对话。'), findsOneWidget);
    expect(find.text('DSH'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
  });
  testWidgets('folder new chat carries the folder and resets the draft', (tester) async {
    final ref = await open(tester, connected: true);
    // A stale selection and an open session are both cleared by the entry.
    ref.read(pendingManagedAgentProvider.notifier).select(agents[0]);
    ref.read(currentSessionProvider.notifier).select('s1');
    await tester.tap(find.text('new-folder'));
    await tester.pumpAndSettle();
    expect(ref.read(currentSessionProvider), isNull);
    expect(ref.read(pendingManagedAgentProvider), isNull);
    expect(ref.read(pendingSessionFolderProvider), 'folder');
  });
  testWidgets('ordinary new chat resets agent and session but leaves a stale folder', (tester) async {
    final ref = await open(tester, connected: true);
    ref.read(pendingSessionFolderProvider.notifier).select('folder');
    ref.read(pendingManagedAgentProvider.notifier).select(agents[0]);
    ref.read(currentSessionProvider.notifier).select('s1');
    await tester.tap(find.text('new'));
    await tester.pumpAndSettle();
    expect(ref.read(currentSessionProvider), isNull);
    expect(ref.read(pendingManagedAgentProvider), isNull);
    // The folder entry is what sets the folder; a plain entry leaves it.
    expect(ref.read(pendingSessionFolderProvider), 'folder');
  });
}

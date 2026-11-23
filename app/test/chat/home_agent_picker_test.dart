import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/features_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/managed_agents_state.dart';
import 'package:dsh_app/state/read_list_identity.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_app/ui/chat/empty_actions.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../workspace/support.dart';
import 'support/harness.dart';

const _workspace = Workspace(workspaceId: 'ws', path: '/cc-spicy', title: 'cc-spicy', sessionIds: []);
final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

class _Host extends ActiveHostController {
  _Host(this.host);
  final HostRef host;
  @override
  HostRef build() => host;
}

class _Workspaces extends WorkspacesController {
  @override
  WorkspacesState build() => const WorkspacesState(status: WorkspacesStatus.ready, workspaces: [_workspace]);
}

/// Records `managedAgent/create` and returns 'managed-new'; honours a failure.
class _ManagedHost extends FakeWorkspaceHost {
  final creates = <(String, String, String)>[];
  bool fail = false;

  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async {
    if (endpoint == 'managedAgent/create') {
      final request = (args['request'] as Map).cast<String, Object?>();
      creates.add((request['workspaceId']! as String, request['agentId']! as String, request['operationId']! as String));
      if (fail) throw const DshHttpException(400, 'response lost');
      return const RpcOk({'sessionId': 'managed-new'});
    }
    return super.call(endpoint, args, timeout: timeout);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tipStart = (_) => 0;
  });
  Future<(ChatHarness, _ManagedHost)> open(WidgetTester tester, {HostRef host = const HostRef.relay('computer')}) async {
    usePhoneView(tester);
    mockClipboard(tester);
    final managed = _ManagedHost();
    final connection = HostConnection(client: DshClient.withCarrier(managed), isLocal: false, kind: HostKind.relay);
    final harness = ChatHarness(
      newChatCatalogs: true,
      states: {'managed-new': const ChatState(loading: false)},
      extra: [
        activeHostProvider.overrideWith(() => _Host(host)),
        readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
        readListLiveConnectionProvider.overrideWithValue(connection),
        workspacesProvider.overrideWith(_Workspaces.new),
        selectedWorkspaceProvider.overrideWithValue(_workspace),
        managedAgentsProvider.overrideWith(
          (ref) async => const [
            ManagedAgentDefinition(
              id: 'claude',
              name: 'Claude Code',
              available: true,
              capabilities: ManagedAgentCapabilities({}),
            ),
            ManagedAgentDefinition(
              id: 'codex',
              name: 'Codex',
              available: true,
              capabilities: ManagedAgentCapabilities({}),
            ),
          ],
        ),
        agentPresetsProvider.overrideWith(
          (ref) async => const [AgentPresetInfo(id: 'standard', isDefault: true), AgentPresetInfo(id: 'minimal')],
        ),
        permissionStateProvider(null).overrideWith(
          (ref) async => const PermissionState(
            options: [PermissionOption('workspace-write', 'Workspace write')],
            hostDefault: 'workspace-write',
          ),
        ),
      ],
    );
    await tester.pumpWidget(testApp(const ChatScreen(), overrides: harness.overrides));
    await pumpFrames(tester, 8);
    return (harness, managed);
  }

  for (final agent in [('claude', 'Claude Code'), ('codex', 'Codex')]) {
    testWidgets('initial home can choose ${agent.$1} without opening the drawer', (tester) async {
      final (harness, managed) = await open(tester);
      expect(find.text('今天想做点什么？'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-chat-agent')), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)), listen: false);
      expect(container.read(currentSessionProvider), isNull);
      await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
      await pumpFrames(tester, 6);
      await tester.tap(find.text(agent.$2));
      await pumpFrames(tester, 6);
      // The pick prepares the empty session on this host/workspace/agent; the
      // screen never leaves the blank home.
      expect(managed.creates.single.$1, 'ws');
      expect(managed.creates.single.$2, agent.$1);
      expect(managed.creates.single.$3, matches(_uuid));
      expect(container.read(currentSessionProvider), isNull);
      expect(find.text('今天想做点什么？'), findsOneWidget);
      expect(find.text(agent.$2), findsOneWidget);
      expect(find.byKey(const ValueKey('new-chat-preset')), findsNothing);
      expect(find.byKey(const ValueKey('new-chat-permission')), findsNothing);
      await tester.enterText(find.byType(TextField), 'hello chosen agent');
      await tester.pump();
      await tester.tap(find.byIcon(AppIcons.send));
      await pumpFrames(tester, 10);
      // The first message reuses the prepared session: no second create, no
      // native session.
      expect(managed.creates.length, 1);
      expect(harness.controllers['managed-new']?.sent, ['hello chosen agent']);
      expect(harness.sessions.creates, 0);
      expect(container.read(currentSessionProvider), 'managed-new');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('choosing DSH on home keeps the existing empty chat', (tester) async {
    final (harness, managed) = await open(tester);
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('Codex'));
    await pumpFrames(tester, 6);
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('DSH').last);
    await pumpFrames(tester, 6);
    expect(find.text('今天想做点什么？'), findsOneWidget);
    // Switching back to DSH keeps the blank home; the earlier Codex pick had
    // already prepared a draft, but no native session exists yet.
    expect(managed.creates.single.$2, 'codex');
    expect(harness.sessions.creates, 0);
    expect(find.byKey(const ValueKey('new-chat-preset')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-chat-permission')), findsOneWidget);
  });

  testWidgets('failed creation keeps draft, agent and workspace; retry reuses the operation id', (tester) async {
    final (harness, managed) = await open(tester);
    await tester.enterText(find.byType(TextField), 'keep this draft');
    await tester.pump();
    managed.fail = true;
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('Codex'));
    await pumpFrames(tester, 8);
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)), listen: false);
    // The prepare failed; nothing navigated and the draft is untouched.
    expect(container.read(currentSessionProvider), isNull);
    expect(container.read(pendingManagedAgentProvider)?.id, 'codex');
    expect(container.read(selectedWorkspaceProvider)?.workspaceId, 'ws');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'keep this draft');
    expect(managed.creates.length, 1);
    expect(managed.creates.single.$3, matches(_uuid));
    expect(harness.sessions.creates, 0);
    // The failed prepare surfaces a retry affordance.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    managed.fail = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await pumpFrames(tester, 8);
    // The retry re-sends the same operation id instead of minting a new one.
    expect(managed.creates.length, 2);
    expect(managed.creates[1].$3, managed.creates[0].$3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(AppIcons.send));
    await pumpFrames(tester, 10);
    expect(harness.controllers['managed-new']?.sent, ['keep this draft']);
    expect(container.read(currentSessionProvider), 'managed-new');
  });
  testWidgets('local home does not offer remote plugin agents', (tester) async {
    await open(tester, host: HostRef.local);
    expect(find.byKey(const ValueKey('new-chat-agent')), findsNothing);
  });
}

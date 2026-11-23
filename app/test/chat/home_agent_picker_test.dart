import 'package:dsh_app/state/models_state.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_app/state/features_state.dart';
import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/managed_agents_state.dart';
import 'package:dsh_app/state/read_list_identity.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_app/ui/chat/empty_actions.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

const _workspace = Workspace(workspaceId: 'ws', path: '/cc-spicy', title: 'cc-spicy', sessionIds: []);

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

class _Creation extends ManagedSessionCreation {
  final calls = <(String, String, String?)>[];
  bool fail = false;
  @override
  Future<String> create(
    WidgetRef ref,
    String workspaceId,
    String agentId, {
    String? folderId,
    bool navigate = true,
    required bool Function() isCurrent,
  }) async {
    expect(isCurrent(), isTrue);
    expect(navigate, isFalse);
    calls.add((workspaceId, agentId, folderId));
    if (fail) throw const DshClosedException('failed');
    return 'managed-new';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tipStart = (_) => 0;
  });
  Future<(ChatHarness, _Creation)> open(WidgetTester tester, {HostRef host = const HostRef.relay('computer')}) async {
    usePhoneView(tester);
    mockClipboard(tester);
    final creation = _Creation();
    final harness = ChatHarness(
      newChatCatalogs: true,
      states: {'managed-new': const ChatState(loading: false)},
      extra: [
        activeHostProvider.overrideWith(() => _Host(host)),
        readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
        readListLiveConnectionProvider.overrideWithValue(fakeConnection),
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
        managedCreationProvider.overrideWithValue(creation),
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
    return (harness, creation);
  }

  for (final agent in [('claude', 'Claude Code'), ('codex', 'Codex')]) {
    testWidgets('initial home can choose ${agent.$1} without opening the drawer', (tester) async {
      final (harness, creation) = await open(tester);
      expect(find.text('今天想做点什么？'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-chat-agent')), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)), listen: false);
      expect(container.read(currentSessionProvider), isNull);
      container
          .read(pendingModelProvider.notifier)
          .select(const ModelSelection(provider: 'native', model: 'native-model'));
      await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
      await pumpFrames(tester, 6);
      await tester.tap(find.text(agent.$2));
      await pumpFrames(tester, 6);
      expect(creation.calls, isEmpty);
      expect(container.read(currentSessionProvider), isNull);
      expect(find.text('今天想做点什么？'), findsOneWidget);
      expect(find.text(agent.$2), findsOneWidget);
      expect(find.byKey(const ValueKey('new-chat-preset')), findsNothing);
      expect(find.byKey(const ValueKey('new-chat-permission')), findsNothing);
      await tester.enterText(find.byType(TextField), 'hello chosen agent');
      await tester.pump();
      await tester.tap(find.byIcon(AppIcons.send));
      await pumpFrames(tester, 10);
      expect(creation.calls, [('ws', agent.$1, null)]);
      expect(harness.controllers['managed-new']?.sent, ['hello chosen agent']);
      expect(harness.controllers['managed-new']?.models, isEmpty);
      expect(harness.sessions.creates, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('choosing DSH on home keeps the existing empty chat', (tester) async {
    final (harness, creation) = await open(tester);
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('Codex'));
    await pumpFrames(tester, 6);
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('DSH').last);
    await pumpFrames(tester, 6);
    expect(find.text('今天想做点什么？'), findsOneWidget);
    expect(creation.calls, isEmpty);
    expect(harness.sessions.creates, 0);
    expect(find.byKey(const ValueKey('new-chat-preset')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-chat-permission')), findsOneWidget);
  });

  testWidgets('changing Agent preserves draft and workspace; failed creation keeps both for retry', (tester) async {
    final (harness, creation) = await open(tester);
    await tester.enterText(find.byType(TextField), 'keep this draft');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-chat-agent')));
    await pumpFrames(tester, 6);
    await tester.tap(find.text('Codex'));
    await pumpFrames(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)), listen: false);
    expect(container.read(selectedWorkspaceProvider)?.workspaceId, 'ws');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'keep this draft');
    expect(creation.calls, isEmpty);
    creation.fail = true;
    await tester.tap(find.byIcon(AppIcons.send));
    await pumpFrames(tester, 8);
    expect(container.read(currentSessionProvider), isNull);
    expect(container.read(pendingManagedAgentProvider)?.id, 'codex');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'keep this draft');
    expect(harness.sessions.creates, 0);
    creation.fail = false;
    await tester.tap(find.byIcon(AppIcons.send));
    await pumpFrames(tester, 10);
    expect(harness.controllers['managed-new']?.sent, ['keep this draft']);
    container.read(currentSessionProvider.notifier).select(null);
    await pumpFrames(tester, 6);
    expect(container.read(pendingManagedAgentProvider), isNull);
  });
  testWidgets('local home does not offer remote plugin agents', (tester) async {
    await open(tester, host: HostRef.local);
    expect(find.byKey(const ValueKey('new-chat-agent')), findsNothing);
  });
}

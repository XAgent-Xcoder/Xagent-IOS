import 'package:dsh_app/state/connection_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../workspace/support.dart';

import 'package:dsh_app/state/drawer_view_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/managed_agents_state.dart';
import 'package:dsh_app/state/read_list_identity.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/chat/managed_agent_picker.dart';
import 'package:dsh_app/ui/shell/drawer/drawer_actions.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const workspace = Workspace(workspaceId: 'ws', path: '/project', title: 'Project', sessionIds: []);
const folder = DrawerFolder(id: 'folder', name: 'My folder');

class _Host extends ActiveHostController {
  @override
  HostRef build() => const HostRef.relay('computer');
}

class _Workspaces extends WorkspacesController {
  _Workspaces(this.empty);
  final bool empty;
  @override
  WorkspacesState build() => WorkspacesState(status: WorkspacesStatus.ready, workspaces: empty ? [] : [workspace]);
}

class _Folders extends DrawerViewController {
  @override
  DrawerView build() => const DrawerView(loaded: true, folders: [folder]);
}

class _Creation extends ManagedSessionCreation {
  final calls = <(String, String, String?)>[];
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
    calls.add((workspaceId, agentId, folderId));
    return 'created';
  }
}

const agents = [
  ManagedAgentDefinition(
    id: 'claude',
    name: 'Claude Code',
    available: true,
    capabilities: ManagedAgentCapabilities({}),
  ),
  ManagedAgentDefinition(id: 'codex', name: 'Codex', available: true, capabilities: ManagedAgentCapabilities({})),
];

class _ManagedHost extends FakeWorkspaceHost {
  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async {
    if (endpoint == 'managedAgent/create') {
      calls.add((endpoint, args));
      return const RpcOk({'sessionId': 'managed-new'});
    }
    return super.call(endpoint, args, timeout: timeout);
  }
}

class _Sessions extends SessionsController {
  @override
  Future<List<SessionSummary>> build() async => [];
  @override
  Future<void> refresh() async {}
}

class _Current extends CurrentSessionController {
  @override
  String? build() => null;
  @override
  void select(String? id) => state = id;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('managed create assigns the returned session to the requested folder before navigation', (tester) async {
    final host = _ManagedHost();
    final client = DshClient.withCarrier(host);
    addTearDown(client.close);
    final connection = HostConnection(client: client, isLocal: false, kind: HostKind.relay);
    late WidgetRef ref;
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, value, _) {
            ref = value;
            return Scaffold(
              body: TextButton(
                onPressed: () => showNewAgentSession(context, ref, () {}, () {}, folderId: folder.id),
                child: const Text('Create'),
              ),
            );
          },
        ),
        overrides: [
          activeHostProvider.overrideWith(_Host.new),
          readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
          readListLiveConnectionProvider.overrideWithValue(connection),
          workspacesProvider.overrideWith(() => _Workspaces(false)),
          selectedWorkspaceProvider.overrideWithValue(workspace),
          managedAgentsProvider.overrideWith((ref) async => agents),
          drawerViewProvider.overrideWith(_Folders.new),
          sessionsProvider.overrideWith(_Sessions.new),
          currentSessionProvider.overrideWith(_Current.new),
        ],
      ),
    );
    final staged = await tester.runAsync(
      () => ref.read(managedCreationProvider).create(ref, 'ws', 'codex', navigate: false, isCurrent: () => true),
    );
    expect(staged, 'managed-new');
    expect(ref.read(currentSessionProvider), isNull, reason: 'draft migration must precede navigation');
    host.calls.clear();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(host.calls.single.$1, 'managedAgent/create');
    expect((host.calls.single.$2['request'] as Map)['agentId'], 'codex');
    expect(ref.read(drawerViewProvider).byId(folder.id)!.sessionIds, ['managed-new']);
    expect(ref.read(currentSessionProvider), 'managed-new');
  });
  Future<_Creation> open(
    WidgetTester tester, {
    bool inFolder = false,
    bool connected = true,
    bool empty = false,
    bool supported = true,
  }) async {
    final creation = _Creation();
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  inFolder ? folderActionsFlow(context, ref, folder) : showNewAgentSession(context, ref, () {}, () {}),
              child: const Text('Open'),
            ),
          ),
        ),
        overrides: [
          activeHostProvider.overrideWith(_Host.new),
          readListIdentityProvider.overrideWithValue(const ReadListIdentity('owner')),
          readListLiveConnectionProvider.overrideWithValue(connected ? fakeConnection : null),
          workspacesProvider.overrideWith(() => _Workspaces(empty)),
          selectedWorkspaceProvider.overrideWithValue(null),
          recentWorkspaceForNewChatProvider.overrideWithValue(null),
          managedAgentsProvider.overrideWith((ref) async => supported ? agents : []),
          managedCreationProvider.overrideWithValue(creation),
          drawerViewProvider.overrideWith(_Folders.new),
        ],
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (inFolder) {
      await tester.tap(find.text('新对话'));
      await tester.pumpAndSettle();
    }
    return creation;
  }

  for (final entry in [('claude', 'Claude Code'), ('codex', 'Codex')]) {
    testWidgets('folder new chat selects ${entry.$1} and carries the folder', (tester) async {
      final creation = await open(tester, inFolder: true);
      expect(find.text('DSH'), findsOneWidget);
      await tester.tap(find.text(entry.$2));
      await tester.pumpAndSettle();
      expect(creation.calls, [('ws', entry.$1, 'folder')]);
    });
  }
  testWidgets('ordinary new chat has no folder assignment', (tester) async {
    final creation = await open(tester);
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(creation.calls, [('ws', 'codex', null)]);
  });
  testWidgets('offline creation stays disabled and explains connection', (tester) async {
    final creation = await open(tester, connected: false);
    expect(find.text('请先连接电脑，再创建 Claude Code 或 Codex 对话。'), findsOneWidget);
    await tester.tap(find.text('Codex'));
    expect(creation.calls, isEmpty);
  });
  testWidgets('empty workspace offers management without creating', (tester) async {
    final creation = await open(tester, empty: true);
    expect(find.text('这台电脑还没有工作区，请先添加工作区。'), findsOneWidget);
    expect(find.text('管理工作区'), findsOneWidget);
    await tester.tap(find.text('Claude Code'));
    expect(creation.calls, isEmpty);
  });
  testWidgets('old host explains unavailable agents and retains DSH', (tester) async {
    await open(tester, supported: false);
    expect(find.text('电脑未提供可用的 Agent。请更新 Xagent 插件并启用托管 Agent。'), findsOneWidget);
    expect(find.text('DSH'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
  });
}

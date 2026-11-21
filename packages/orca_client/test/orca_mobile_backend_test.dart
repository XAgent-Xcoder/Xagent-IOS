import 'dart:async';

import 'package:orca_client/orca_client.dart';
import 'package:test/test.dart';

/// Captures every RPC the backend sends, so a test can assert the envelope
/// (fence, operation id, fingerprint) without a live host.
class _FakeTransport implements OrcaRpcTransport {
  final sent = <(String, Map<String, dynamic>)>[];
  final _subEvents = <Map<String, dynamic>>[];
  final _history = <Map<String, dynamic>>[];

  int _nextFence = 1;

  void enqueueHistory(Map<String, dynamic> page) => _history.add(page);

  void enqueueSubEvent(Map<String, dynamic> event) => _subEvents.add(event);

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 30)}) async {
    sent.add((method, params));
    return switch (method) {
      'aiVault.listSessions' => {
          'sessions': [
            {
              'agent': 'dsh',
              'sessionId': 'native-1',
              'title': 'T',
              'structuredSession': {'sessionId': 'struct-1', 'workspaceId': 'wt'},
              'messageCount': 1,
            },
          ],
          'issues': [],
        },
      'agentSession.create' => {
          'ok': true,
          'replayed': false,
          'fence': _nextFence++,
          'cursor': {'epoch': 'ep', 'sequence': 0},
          'value': {
            'sessionId': params['sessionId'],
            'fence': _nextFence - 1,
            'page': {'items': [], 'submissions': [], 'window': {}, 'hasOlder': false, 'hasNewer': false},
            'unconfirmedClientMessageIds': <String>[],
          },
        },
      'agentSession.history' => _history.isNotEmpty ? _history.removeAt(0) : {
            'sessionId': params['sessionId'],
            'fence': 5,
            'direction': 'tail',
            'items': [{'id': 'i1', 'role': 'user', 'text': 'hi'}],
            'submissions': [],
            'window': {'oldest': null, 'newest': {'epoch': 'ep', 'sequence': 1}, 'nextCursor': null},
            'hasOlder': true,
            'hasNewer': false,
          },
      'agentSession.send' => {
          'ok': true,
          'replayed': false,
          'fence': _nextFence,
          'cursor': {'epoch': 'ep', 'sequence': 1},
          'value': {'clientMessageId': 'cm-1', 'submission': {'state': 'accepted'}},
        },
      'agentSession.modelCatalog' => {
          'origin': 'live-session',
          'models': [
            {'key': 'm1', 'label': 'Model 1', 'defaultSelection': true},
          ],
          'fetchedAt': 1,
        },
      _ => {'ok': true, 'value': {}},
    };
  }

  @override
  Stream<Map<String, dynamic>> subscribe(String sessionId, {Map<String, dynamic>? cursor}) {
    final controller = StreamController<Map<String, dynamic>>();
    for (final event in _subEvents) {
      controller.add(event);
      if (event['type'] == 'end') break;
    }
    if (_subEvents.isNotEmpty && _subEvents.last['type'] != 'end') {
      _subEvents.add({'type': 'end'});
    }
    _subEvents.clear();
    return controller.stream;
  }

  @override
  Future<void> close() async {}
}

MobileChatBackend _backend(_FakeTransport transport) =>
    OrcaMobileBackend(transport);

void main() {
  test('listConversations maps aiVault rows to the three-layer identity', () async {
    final t = _FakeTransport();
    final conversations = await _backend(t).listConversations();
    expect(conversations, hasLength(1));
    expect(conversations.single.agent, 'dsh');
    expect(conversations.single.nativeSessionId, 'native-1');
    expect(conversations.single.structuredSessionId, 'struct-1');
    expect(conversations.single.isWritable, isTrue);
  });

  test('createSession records the host fence and returns it', () async {
    final t = _FakeTransport();
    final created = await _backend(t).createSession(agent: 'dsh', worktree: 'wt', firstMessage: 'hello');
    expect(created.sessionId, isNotEmpty);
    expect(created.fence, greaterThan(0));
    final (method, params) = t.sent.single;
    expect(method, 'agentSession.create');
    expect(params['envelope']['expectedRuntimeFence'], isNull);
    expect(params['agent'], 'dsh');
  });

  test('send carries the recorded fence and records the new one', () async {
    final t = _FakeTransport();
    final b = _backend(t);
    final created = await b.createSession(agent: 'dsh', worktree: 'wt');
    t.sent.clear();
    await b.send(created.sessionId, 'continue');
    final (method, params) = t.sent.single;
    expect(method, 'agentSession.send');
    expect(params['envelope']['expectedRuntimeFence'], isNotNull);
    expect(params['body']['blocks'], isA<List>());
  });

  test('send without a recorded fence throws', () async {
    final t = _FakeTransport();
    final b = _backend(t);
    expect(() => b.send('unknown-sid', 'x'), throwsA(isA<StateError>()));
  });

  test('openConversation returns a page and streams snapshot then batch', () async {
    final t = _FakeTransport();
    t.enqueueSubEvent({'type': 'snapshot', 'sessionId': 's', 'fence': 9, 'page': {'items': [{'id': 'i0', 'role': 'assistant', 'text': 'snap'}], 'window': {}, 'hasOlder': false, 'hasNewer': false}});
    t.enqueueSubEvent({'type': 'batch', 'sessionId': 's', 'batch': {'cursor': {'epoch': 'ep', 'sequence': 2}, 'items': [{'id': 'i1', 'role': 'assistant', 'text': 'live'}], 'removedItemIds': [], 'submissions': []}, 'fence': 10});
    t.enqueueSubEvent({'type': 'end'});
    final b = _backend(t);
    final open = await b.openConversation('s');
    expect(open.history.fence, isNotNull);
    expect(open.history.items, hasLength(1));
    final events = await open.events.toList();
    expect(events.map((e) => e.type).toList(), [
      SubscribeEventType.snapshot,
      SubscribeEventType.batch,
      SubscribeEventType.end,
    ]);
  });

  test('modelCatalog parses the host catalog', () async {
    final t = _FakeTransport();
    final catalog = await _backend(t).modelCatalog(agent: 'dsh');
    expect(catalog.origin, ModelCatalogOrigin.liveSession);
    expect(catalog.models.single.key, 'm1');
    expect(catalog.models.single.isDefault, isTrue);
  });
}

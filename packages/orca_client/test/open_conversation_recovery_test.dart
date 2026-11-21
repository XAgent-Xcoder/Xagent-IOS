import 'dart:async';

import 'package:orca_client/orca_client.dart';
import 'package:test/test.dart';

/// A transport whose subscribe emits a controlled sequence of frames.
class _ScriptedTransport implements OrcaRpcTransport {
  final frames = <Map<String, dynamic>>[];
  final sent = <(String, Map<String, dynamic>)>[];

  void enqueueFrame(Map<String, dynamic> f) => frames.add(f);

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 30)}) async {
    sent.add((method, params));
    return switch (method) {
      'agentSession.history' => {
          'sessionId': 's', 'fence': 1, 'direction': 'tail',
          'items': [
            {'id': 'a', 'role': 'user', 'text': 'a'},
          ],
          'submissions': [],
          'window': {'oldest': null, 'newest': {'epoch': 'ep', 'sequence': 1}, 'nextCursor': null},
          'hasOlder': true, 'hasNewer': false,
        },
      _ => {'ok': true, 'value': {}},
    };
  }

  @override
  Stream<Map<String, dynamic>> subscribe(String sessionId, {Map<String, dynamic>? cursor}) async* {
    for (final f in frames) {
      yield f;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('OpenConversation.recovery folds events: dedupe + dispatch + recover', () async {
    final t = _ScriptedTransport();
    t.enqueueFrame({
      'type': 'batch', 'sessionId': 's', 'fence': 1,
      'batch': {
        'cursor': {'epoch': 'ep', 'sequence': 2},
        'items': [
          {'id': 'a', 'role': 'user', 'text': 'a'},  // dup of initial history item
          {'id': 'b', 'role': 'assistant', 'text': 'b'},
        ],
        'removedItemIds': [],
        'submissions': [
          {'clientMessageId': 'cm-1', 'state': 'accepted'},
        ],
      },
    });
    t.enqueueFrame({'type': 'end'});

    final b = OrcaMobileBackend(t);
    final open = await b.openConversation('s');
    final done = Completer<void>();
    open.recovery.onRecovered = () => done.complete();

    await open.events.toList();
    await done.future.timeout(const Duration(seconds: 1));

    // The initial history item 'a' + the batch item 'b' (a is deduped).
    expect(open.recovery.itemIds, ['a', 'b']);
    expect(open.recovery.dispatchStates, {'cm-1': DispatchState.accepted});
    expect(open.recovery.isRecovered, isTrue);
    expect(open.recovery.fence, 1);
    await b.close();
  });

  test('reset frame with a higher fence fires onReattach via recovery', () async {
    final t = _ScriptedTransport();
    t.enqueueFrame({
      'type': 'reset', 'sessionId': 's', 'fence': 9, 'reset': 'host-restarted',
      'page': {
        'items': [
          {'id': 'x', 'role': 'assistant', 'text': 'x'},
        ],
        'window': {}, 'hasOlder': false, 'hasNewer': false,
      },
    });
    t.enqueueFrame({'type': 'end'});

    final b = OrcaMobileBackend(t);
    final open = await b.openConversation('s');
    final reattached = <int>[];
    open.recovery.onReattach = (fence) => reattached.add(fence);

    await open.events.toList();
    expect(reattached, [9]);
    expect(open.recovery.itemIds, ['x']);
    await b.close();
  });
}

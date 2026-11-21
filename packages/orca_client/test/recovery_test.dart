import 'dart:async';

import 'package:orca_client/orca_client.dart';
import 'package:test/test.dart';

/// Drives a [SessionRecovery] with synthetic subscribe frames, asserting the
/// recovery contract of design doc §5.6: snapshot overwrites local state,
/// items dedupe by itemId, a fence jump (host restart) triggers re-attach,
/// and a submit's dispatch state is surfaced (never swallowed).
void main() {
  test('dedupes items by itemId across snapshot and batch', () {
    final recovery = SessionRecovery();
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'snapshot', 'sessionId': 's', 'fence': 1,
      'page': {
        'items': [
          {'id': 'a', 'role': 'user', 'text': 'x'},
          {'id': 'b', 'role': 'assistant', 'text': 'y'},
        ],
        'window': {}, 'hasOlder': false, 'hasNewer': false,
      },
    }));
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'batch', 'sessionId': 's', 'fence': 1,
      'batch': {
        'cursor': {'epoch': 'ep', 'sequence': 2},
        'items': [
          {'id': 'b', 'role': 'assistant', 'text': 'y'},  // duplicate
          {'id': 'c', 'role': 'assistant', 'text': 'z'},
        ],
        'removedItemIds': [], 'submissions': [],
      },
    }));
    expect(recovery.itemIds, ['a', 'b', 'c']);
  });

  test('snapshot overwrites prior local state', () {
    final recovery = SessionRecovery();
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'snapshot', 'sessionId': 's', 'fence': 1,
      'page': {
        'items': [
          {'id': 'old', 'role': 'user', 'text': 'old'},
        ],
        'window': {}, 'hasOlder': false, 'hasNewer': false,
      },
    }));
    // A re-snapshot after reconnect replaces the item set entirely.
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'snapshot', 'sessionId': 's', 'fence': 2,
      'page': {
        'items': [
          {'id': 'new', 'role': 'user', 'text': 'new'},
        ],
        'window': {}, 'hasOlder': false, 'hasNewer': false,
      },
    }));
    expect(recovery.itemIds, ['new']);
    expect(recovery.fence, 2);
  });

  test('fence jump (host restart) triggers onReattach', () {
    final recovery = SessionRecovery();
    final reattached = <int>[];
    recovery.onReattach = (fence) => reattached.add(fence);
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'snapshot', 'sessionId': 's', 'fence': 1,
      'page': {'items': [], 'window': {}, 'hasOlder': false, 'hasNewer': false},
    }));
    // A reset frame carrying a higher fence is the host-restart signal.
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'reset', 'sessionId': 's', 'fence': 7, 'reset': 'host-restarted',
      'page': {'items': [], 'window': {}, 'hasOlder': false, 'hasNewer': false},
    }));
    expect(reattached, [7]);
  });

  test('dispatch state is surfaced, never swallowed', () {
    final recovery = SessionRecovery();
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'batch', 'sessionId': 's', 'fence': 1,
      'batch': {
        'cursor': {'epoch': 'ep', 'sequence': 1},
        'items': [],
        'removedItemIds': [],
        'submissions': [
          {'clientMessageId': 'cm-1', 'state': 'accepted'},
          {'clientMessageId': 'cm-2', 'state': 'pending'},
        ],
      },
    }));
    expect(recovery.dispatchStates, {
      'cm-1': DispatchState.accepted,
      'cm-2': DispatchState.pending,
    });
  });

  test('end frame marks recovery complete', () async {
    final recovery = SessionRecovery();
    final done = Completer<void>();
    recovery.onRecovered = () => done.complete();
    recovery.process(SubscribeEvent.fromFrame({
      'type': 'snapshot', 'sessionId': 's', 'fence': 1,
      'page': {'items': [], 'window': {}, 'hasOlder': false, 'hasNewer': false},
    }));
    expect(done.isCompleted, isFalse); // snapshot alone is not recovery
    recovery.process(SubscribeEvent.fromFrame({'type': 'end'}));
    await done.future.timeout(const Duration(seconds: 1));
    expect(recovery.isRecovered, isTrue);
  });
}

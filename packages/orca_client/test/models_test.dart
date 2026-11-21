import 'package:orca_client/orca_client.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationSummary', () {
    test('parses an aiVault row with structuredSession', () {
      final row = ConversationSummary.fromRow({
        'agent': 'claude',
        'sessionId': 'abc-123',
        'title': 'Refactor auth',
        'cwd': '/home/dev/project',
        'branch': 'feat/auth',
        'model': 'claude-sonnet-4-5',
        'messageCount': 12,
        'structuredSession': {'sessionId': 'struct-456', 'workspaceId': 'wt-1'},
      });
      expect(row.agent, 'claude');
      expect(row.nativeSessionId, 'abc-123');
      expect(row.structuredSessionId, 'struct-456');
      expect(row.isWritable, isTrue);
      expect(row.title, 'Refactor auth');
      expect(row.cwd, '/home/dev/project');
      expect(row.branch, 'feat/auth');
      expect(row.model, 'claude-sonnet-4-5');
      expect(row.messageCount, 12);
    });

    test('parses an aiVault row without structuredSession (read-only)', () {
      final row = ConversationSummary.fromRow({
        'agent': 'dsh',
        'sessionId': 'dsh-789',
        'title': 'Old session',
        'cwd': null,
        'branch': null,
        'model': null,
        'messageCount': 3,
      });
      expect(row.agent, 'dsh');
      expect(row.nativeSessionId, 'dsh-789');
      expect(row.structuredSessionId, isNull);
      expect(row.isWritable, isFalse);
    });
  });

  group('HistoryPage', () {
    test('parses a tail history page with cursor', () {
      final page = HistoryPage.fromResult({
        'sessionId': 's1',
        'epoch': 'ep-1',
        'fence': 42,
        'direction': 'tail',
        'items': [
          {'id': 'item-1', 'role': 'user', 'text': 'hello'},
          {'id': 'item-2', 'role': 'assistant', 'text': 'hi'},
        ],
        'submissions': [],
        'window': {'oldest': {'epoch': 'ep-1', 'sequence': 0}, 'newest': {'epoch': 'ep-1', 'sequence': 2}, 'nextCursor': null},
        'hasOlder': true,
        'hasNewer': false,
      });
      expect(page.fence, 42);
      expect(page.items, hasLength(2));
      expect(page.items[0].id, 'item-1');
      expect(page.hasOlder, isTrue);
      expect(page.nextCursor, isNull);
    });

    test('parses a before page with nextCursor for further paging', () {
      final page = HistoryPage.fromResult({
        'sessionId': 's1',
        'epoch': 'ep-1',
        'direction': 'before',
        'items': [
          {'id': 'item-0', 'role': 'user', 'text': 'old'},
        ],
        'submissions': [],
        'window': {'oldest': null, 'newest': {'epoch': 'ep-1', 'sequence': 0}, 'nextCursor': {'epoch': 'ep-1', 'sequence': 0}},
        'hasOlder': true,
        'hasNewer': true,
      });
      expect(page.nextCursor, isNotNull);
      expect(page.nextCursor!.epoch, 'ep-1');
      expect(page.nextCursor!.sequence, 0);
    });
  });

  group('SubscribeEvent', () {
    test('parses a snapshot frame', () {
      final event = SubscribeEvent.fromFrame({
        'type': 'snapshot',
        'sessionId': 's1',
        'fence': 7,
        'page': {
          'sessionId': 's1', 'epoch': 'ep', 'items': [], 'submissions': [],
          'window': {'oldest': null, 'newest': null, 'nextCursor': null},
          'hasOlder': false, 'hasNewer': false,
        },
        'queuedMessages': [{'messageId': 'qm-1', 'text': 'queued prompt'}],
      });
      expect(event.type, SubscribeEventType.snapshot);
      expect(event.fence, 7);
      expect(event.queuedMessages, hasLength(1));
    });

    test('parses a batch frame with cursor', () {
      final event = SubscribeEvent.fromFrame({
        'type': 'batch',
        'sessionId': 's1',
        'batch': {
          'cursor': {'epoch': 'ep', 'sequence': 10},
          'items': [{'id': 'item-3', 'role': 'assistant', 'text': 'response'}],
          'removedItemIds': [],
          'submissions': [],
        },
        'fence': 8,
      });
      expect(event.type, SubscribeEventType.batch);
      expect(event.batchCursor!.sequence, 10);
      expect(event.items, hasLength(1));
    });

    test('parses an end frame', () {
      final event = SubscribeEvent.fromFrame({'type': 'end'});
      expect(event.type, SubscribeEventType.end);
    });
  });

  group('ModelCatalog', () {
    test('parses a live-session catalog', () {
      final catalog = ModelCatalog.fromResult({
        'origin': 'live-session',
        'models': [
          {'key': 'claude-sonnet-4-5', 'label': 'Claude Sonnet 4.5'},
          {'key': 'claude-opus-4-5', 'label': 'Claude Opus 4.5'},
        ],
        'fetchedAt': 1700000000000,
      });
      expect(catalog.origin, ModelCatalogOrigin.liveSession);
      expect(catalog.models, hasLength(2));
      expect(catalog.models.first.key, 'claude-sonnet-4-5');
      expect(catalog.models.first.label, 'Claude Sonnet 4.5');
    });

    test('parses an unavailable catalog', () {
      final catalog = ModelCatalog.fromResult({'unavailable': true});
      expect(catalog.origin, ModelCatalogOrigin.unavailable);
      expect(catalog.models, isEmpty);
    });
  });
}

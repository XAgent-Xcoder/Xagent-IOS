import 'history_page.dart';

/// The kind of frame delivered by `agentSession.subscribe`.
enum SubscribeEventType { snapshot, batch, reset, end }

/// A frame from the `agentSession.subscribe` stream.
///
/// The event shape mirrors the host's `AgentSessionSubscribeEvent` union
/// (`snapshot` / `batch` / `reset` / `end`). The cursor on a `batch` frame is
/// the journal cursor the batch was cut from; `snapshot` and `reset` always
/// carry a fence, a `batch` frame's fence is optional.
class SubscribeEvent {
  const SubscribeEvent._({
    required this.type,
    this.fence,
    this.batchCursor,
    this.items = const [],
    this.queuedMessages = const [],
    this.submissions = const [],
    this.sessionId,
  });

  final SubscribeEventType type;

  /// The runtime fence the frame was delivered under.
  final int? fence;

  /// The journal cursor the batch was cut from (`batch` frames only).
  final JournalCursor? batchCursor;

  /// The rendered items carried by this frame.
  final List<HistoryItem> items;

  /// Queued messages reported alongside the frame.
  final List<Map<String, dynamic>> queuedMessages;

  /// Submission dispatch states the host reported (`clientMessageId` +
  /// `state`), present on `batch` frames.
  final List<Map<String, dynamic>> submissions;

  final String? sessionId;

  /// Parses an `AgentSessionSubscribeEvent` wire object.
  factory SubscribeEvent.fromFrame(Map<String, dynamic> frame) {
    final type = frame['type'];
    final eventKind = type == 'reset'
        ? SubscribeEventType.reset
        : SubscribeEventType.snapshot;
    final items = <HistoryItem>[];
    switch (type) {
      case 'snapshot':
      case 'reset':
        final page = frame['page'] is Map<String, dynamic>
            ? frame['page'] as Map<String, dynamic>
            : const {};
        if (page['items'] is List) {
          for (final raw in page['items'] as List) {
            if (raw is Map<String, dynamic>) {
              items.add(HistoryItem(
                id: raw['id'] is String ? raw['id'] as String : '',
                role: raw['role'] is String ? raw['role'] as String : '',
                text: raw['text'] is String ? raw['text'] as String : '',
              ));
            }
          }
        }
        final queued = _parseQueued(frame);
        return SubscribeEvent._(
          type: eventKind,
          fence: frame['fence'] is int ? frame['fence'] as int : null,
          items: items,
          queuedMessages: queued,
          sessionId: frame['sessionId'] is String ? frame['sessionId'] as String : null,
        );
      case 'batch':
        final batch = frame['batch'] is Map<String, dynamic>
            ? frame['batch'] as Map<String, dynamic>
            : const {};
        if (batch['items'] is List) {
          for (final raw in batch['items'] as List) {
            if (raw is Map<String, dynamic>) {
              items.add(HistoryItem(
                id: raw['id'] is String ? raw['id'] as String : '',
                role: raw['role'] is String ? raw['role'] as String : '',
                text: raw['text'] is String ? raw['text'] as String : '',
              ));
            }
          }
        }
        final cursorRaw = batch['cursor'];
        final submissions = <Map<String, dynamic>>[];
        if (batch['submissions'] is List) {
          for (final raw in batch['submissions'] as List) {
            if (raw is Map<String, dynamic>) submissions.add(raw);
          }
        }
        return SubscribeEvent._(
          type: SubscribeEventType.batch,
          fence: frame['fence'] is int ? frame['fence'] as int : null,
          batchCursor: cursorRaw is Map<String, dynamic>
              ? JournalCursor.fromJson(cursorRaw)
              : null,
          items: items,
          submissions: submissions,
          sessionId: frame['sessionId'] is String ? frame['sessionId'] as String : null,
        );
      default:
        return const SubscribeEvent._(type: SubscribeEventType.end);
    }
  }

  static List<Map<String, dynamic>> _parseQueued(Map<String, dynamic> frame) {
    final queued = <Map<String, dynamic>>[];
    if (frame['queuedMessages'] is List) {
      for (final q in frame['queuedMessages'] as List) {
        if (q is Map<String, dynamic>) queued.add(q);
      }
    }
    return queued;
  }
}

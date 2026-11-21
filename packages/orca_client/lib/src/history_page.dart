/// A single item in a history page (a rendered journal entry).
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.role,
    required this.text,
  });

  /// Journal item ID (`itemId` on the wire).
  final String id;

  /// Role: `user`, `assistant`, `tool`, etc.
  final String role;

  /// Rendered text content.
  final String text;
}

/// A journal cursor: `{epoch, sequence}`.
class JournalCursor {
  const JournalCursor(this.epoch, this.sequence);

  final String epoch;
  final int sequence;

  factory JournalCursor.fromJson(Map<String, dynamic> json) => JournalCursor(
        json['epoch'] as String,
        json['sequence'] as int,
      );

  Map<String, dynamic> toJson() => {'epoch': epoch, 'sequence': sequence};

  @override
  bool operator ==(Object other) =>
      other is JournalCursor && other.epoch == epoch && other.sequence == sequence;

  @override
  int get hashCode => Object.hash(epoch, sequence);
}

/// A history page from `agentSession.history`.
class HistoryPage {
  const HistoryPage({
    required this.fence,
    required this.items,
    required this.hasOlder,
    required this.hasNewer,
    this.nextCursor,
    this.sessionId,
    this.epoch,
    this.queuedMessages = const [],
  });

  /// The runtime fence the page was read under (from the `page.fence` field).
  final int? fence;

  /// The rendered items on this page.
  final List<HistoryItem> items;

  /// Whether older items exist before [items].first.
  final bool hasOlder;

  /// Whether newer items exist after [items].last.
  final bool hasNewer;

  /// The cursor for the next page in the same direction, or null when there
  /// is no further page.
  final JournalCursor? nextCursor;

  /// The session ID this page belongs to.
  final String? sessionId;

  /// The journal epoch the page was read under.
  final String? epoch;

  /// Queued messages reported alongside the page.
  final List<Map<String, dynamic>> queuedMessages;

  /// Parses the `AgentSessionHistoryPage` wire object.
  factory HistoryPage.fromResult(Map<String, dynamic> result) {
    final window = result['window'] is Map<String, dynamic>
        ? result['window'] as Map<String, dynamic>
        : const {};
    final nextCursorRaw = window['nextCursor'];
    final items = <HistoryItem>[];
    if (result['items'] is List) {
      for (final raw in result['items'] as List) {
        if (raw is Map<String, dynamic>) {
          items.add(HistoryItem(
            id: raw['id'] is String ? raw['id'] as String : '',
            role: raw['role'] is String ? raw['role'] as String : '',
            text: raw['text'] is String ? raw['text'] as String : '',
          ));
        }
      }
    }
    final queued = <Map<String, dynamic>>[];
    if (result['queuedMessages'] is List) {
      for (final q in result['queuedMessages'] as List) {
        if (q is Map<String, dynamic>) queued.add(q);
      }
    }
    return HistoryPage(
      fence: result['fence'] is int ? result['fence'] as int : null,
      items: items,
      hasOlder: result['hasOlder'] == true,
      hasNewer: result['hasNewer'] == true,
      nextCursor: nextCursorRaw is Map<String, dynamic>
          ? JournalCursor.fromJson(nextCursorRaw)
          : null,
      sessionId: result['sessionId'] is String ? result['sessionId'] as String : null,
      epoch: result['epoch'] is String ? result['epoch'] as String : null,
      queuedMessages: queued,
    );
  }
}

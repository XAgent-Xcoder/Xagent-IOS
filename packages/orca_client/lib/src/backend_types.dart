/// The dispatch state of a client submission, as the host reports it.
enum DispatchState { pending, accepted }

/// The direction of a history read.
enum HistoryDirection { tail, before, after }

/// The process-level connection state of a backend, mirroring the host's
/// notion of connecting / reconnecting / connected / closed.
enum ConnectionState { disconnected, connecting, connected, reconnecting, closed }

/// A question answer for `respondToQuestion`.
class QuestionAnswer {
  const QuestionAnswer({
    required this.questionId,
    required this.optionIds,
    this.other,
  });

  final String questionId;
  final List<String> optionIds;

  /// Free-text answer (`other`), when the answer is not one of the options.
  final String? other;
}

/// The result of `createSession`: the new session's identity and fence.
class CreatedSession {
  const CreatedSession({
    required this.sessionId,
    required this.fence,
    this.unconfirmedClientMessageIds = const [],
  });

  final String sessionId;

  /// The host-reported runtime fence the new session starts under.
  final int fence;

  /// Client message IDs that were queued but not yet confirmed (firstMessage
  /// that is still in flight).
  final List<String> unconfirmedClientMessageIds;
}

/// The result of `send`: a delivery receipt.
class SendReceipt {
  const SendReceipt({
    required this.clientMessageId,
    required this.fence,
    this.queued = false,
    this.queuePosition,
    this.queueState,
  });

  /// The client-generated message ID (stable across retries of the same
  /// operation, via `clientOperationId` replay).
  final String clientMessageId;

  /// The host-reported runtime fence after the send.
  final int fence;

  /// Whether the send was queued (the host was mid-turn) rather than
  /// dispatched immediately.
  final bool queued;

  /// Queue position when [queued] is true.
  final int? queuePosition;

  /// Queue state: `waiting`, `dispatched`, `returned`, `withdrawn`.
  final String? queueState;
}

/// The result of a queued-message operation (delete/move).
class QueueReceipt {
  const QueueReceipt({
    required this.deleted,
    required this.messageId,
    this.disposition,
  });

  final bool deleted;
  final String messageId;

  /// Disposition: `missing`, `dispatched`, `withdrawn` (or null).
  final String? disposition;
}

/// The result of `setModel`: the reconciled option values the host reports
/// back (the UI must not trust a local-only change).
class SetOptionResult {
  const SetOptionResult({
    required this.key,
    required this.value,
    this.options = const {},
  });

  final String key;
  final String value;

  /// The full set of effective option values the host now reports (read-back).
  final Map<String, String> options;
}

import 'dart:async';

import 'backend_types.dart';
import 'conversation_summary.dart';
import 'history_page.dart';
import 'model_catalog.dart';
import 'recovery.dart';
import 'subscribe_event.dart';

/// Capabilities a backend reports. The DSH backend returns its real
/// capabilities; the Orca backend returns `true` for what Orca supports and
/// `false` for DSH-only features (terminal, subagent routing, etc.). The UI
/// hides entries whose capability is false — it never invents behavior.
class BackendCapabilities {
  const BackendCapabilities({
    this.supportsTerminal = false,
    this.supportsFileUpload = false,
    this.supportsWorkspaceUpload = false,
    this.supportsSessionSearch = false,
    this.supportsSessionDeletion = false,
    this.supportsModelSwitch = true,
    this.supportsApproval = true,
    this.supportsQueue = true,
    this.supportsHistoryPaging = true,
  });

  final bool supportsTerminal;
  final bool supportsFileUpload;
  final bool supportsWorkspaceUpload;
  final bool supportsSessionSearch;
  final bool supportsSessionDeletion;
  final bool supportsModelSwitch;
  final bool supportsApproval;
  final bool supportsQueue;
  final bool supportsHistoryPaging;
}

/// The unified chat-backend contract the mobile UI is written against. Both
/// DSH and Orca implement it; the UI holds a [MobileChatBackend] instead of a
/// concrete `DshClient`. See the design doc §3.2 for the minimal contract.
///
/// The runtime fence is tracked internally by each implementation (recorded on
/// `openConversation` / `createSession`, refreshed on every mutation) so the
/// caller never threads it through. A send without a recorded fence fails —
/// the backend must have seen the session first.
abstract class MobileChatBackend {
  /// The backend's capabilities. UI hides entries whose flag is false.
  BackendCapabilities get capabilities;

  /// A stream of process-level connection state changes (disconnected →
  /// connecting → connected → reconnecting → closed). The UI uses this to
  /// show a syncing indicator and to trigger re-subscribe after a reconnect.
  Stream<ConnectionState> get connectionStates;

  /// Current connection state (a convenience; the stream is authoritative).
  ConnectionState get connectionState;

  /// Trigger a reconnect of the underlying transport.
  void reconnect();

  // ── Conversation listing ──────────────────────────────────────────────────

  /// Lists all conversations on this backend, newest first. Each row carries
  /// the three-layer session identity (`agent`, `nativeSessionId`, optional
  /// `structuredSessionId`). A row without `structuredSessionId` is read-only
  /// (no `agentSession.*` writes possible).
  Future<List<ConversationSummary>> listConversations();

  // ── Open / history / subscribe ────────────────────────────────────────────

  /// Opens a conversation: returns the initial history page (tail direction)
  /// and a subscription handle for live events. The caller uses [OpenConversation]
  /// to drive both paging (older history) and the live subscription.
  Future<OpenConversation> openConversation(String sessionId);

  /// Creates a new session. [agent] is the harness identifier (e.g. `dsh`,
  /// `claude`). [worktree] is the host worktree selector string. If
  /// [firstMessage] is non-null it is queued as the first user message and
  /// dispatched when the session starts (the host's atRest create semantics —
  /// it cannot be re-sent afterwards, per §5.2).
  Future<CreatedSession> createSession({
    required String agent,
    required String worktree,
    String? firstMessage,
  });

  /// Sends a continuation message to an existing session. The runtime fence is
  /// the one this backend last recorded for [sessionId].
  Future<SendReceipt> send(String sessionId, String text);

  // ── Cancel / queue ────────────────────────────────────────────────────────

  /// Cancels the currently-running turn.
  Future<void> cancel(String sessionId);

  /// Deletes a queued message.
  Future<QueueReceipt> deleteQueued(String sessionId, String messageId);

  /// Moves a queued message before/after another.
  Future<void> moveQueued(String sessionId, String messageId,
      {String? beforeMessageId, String? afterMessageId});

  /// Edits a queued message's text. [expectedBodyFingerprint] is the host's
  /// CAS guard against editing a body that changed under us.
  Future<void> updateQueued(String sessionId, String messageId, String text,
      {required String expectedBodyFingerprint});

  /// Resumes processing of the queue after a cancel (the host's
  /// `queuedMessagesResume` semantics).
  Future<void> resumeQueue(String sessionId);

  // ── Approvals / questions ────────────────────────────────────────────────

  /// Responds to an approval request. [itemId] and [expectedRevision] are the
  /// host's CAS identifiers; [optionId] is the approval choice.
  Future<void> respondToApproval(String sessionId, String itemId,
      int expectedRevision, String optionId);

  /// Responds to a question. [answers] is one entry per question.
  Future<void> respondToQuestion(String sessionId, String itemId,
      int expectedRevision, List<QuestionAnswer> answers);

  // ── Models ────────────────────────────────────────────────────────────────

  /// Reads the host's actual model catalog (no waiting for an attach).
  Future<ModelCatalog> modelCatalog({required String agent});

  /// Switches a session's model. Returns the host's read-back of the new
  /// effective option values — the UI must sync to this, not just flip a
  /// local flag.
  Future<SetOptionResult> setModel(String sessionId, String key, String value);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Closes the backend and releases all resources.
  Future<void> close();
}

/// The handle returned by [MobileChatBackend.openConversation]: the initial
/// history page plus a live event stream and a method to page back further.
class OpenConversation {
  OpenConversation({
    required this.history,
    required StreamController<SubscribeEvent> eventController,
    required Future<HistoryPage> Function(JournalCursor cursor) onPageBack,
    SessionRecovery? recovery,
  })
      : recovery = recovery ?? SessionRecovery(),
        _eventController = eventController,
        _onPageBack = onPageBack;

  final HistoryPage history;
  final StreamController<SubscribeEvent> _eventController;
  final Future<HistoryPage> Function(JournalCursor cursor) _onPageBack;

  /// The recovery state machine (design doc §5.6): folds every subscribe frame
  /// into local state, dedupes by itemId, surfaces dispatch states, and fires
  /// `onReattach` on a fence jump. The UI reads its state from here rather
  /// than re-implementing the fold.
  final SessionRecovery recovery;

  /// Live events from the host (snapshot, batch, reset, end).
  Stream<SubscribeEvent> get events => _eventController.stream;

  /// Pages back further into the history (older items).
  /// [cursor] is the `nextCursor` from the current history page.
  Future<HistoryPage> pageBack(JournalCursor cursor) => _onPageBack(cursor);

  /// Cancels the subscription and closes the stream.
  Future<void> dispose() => _eventController.close();
}

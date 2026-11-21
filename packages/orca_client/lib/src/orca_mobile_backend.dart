import 'dart:async';

import 'backend_types.dart';
import 'conversation_summary.dart';
import 'history_page.dart';
import 'model_catalog.dart';
import 'mobile_chat_backend.dart';
import 'orca_rpc_transport.dart';
import 'recovery.dart';
import 'session_mutation.dart';
import 'subscribe_event.dart';

/// The Orca implementation of [MobileChatBackend].
///
/// Wraps a [OrcaRpcTransport] (typically [LegacyOrcaClient]) and provides the
/// unified contract the mobile UI is written against. The runtime fence is
/// tracked internally: recorded on `openConversation` / `createSession`,
/// refreshed on every mutation, and carried as `expectedRuntimeFence` on each
/// subsequent write. A send for a session whose fence was never recorded
/// throws — the backend must have seen the session first.
class OrcaMobileBackend implements MobileChatBackend {
  OrcaMobileBackend(this._transport);

  final OrcaRpcTransport _transport;
  final _fences = <String, int>{};
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _connections = <String, StreamSubscription<Map<String, dynamic>>>{};
  bool _closed = false;
  ConnectionState _state = ConnectionState.disconnected;

  void _setState(ConnectionState next) {
    if (next == _state || _closed) return;
    _state = next;
    _stateController.add(next);
  }

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
        supportsTerminal: false,
        supportsFileUpload: false,
        supportsWorkspaceUpload: false,
        supportsSessionSearch: false,
        supportsSessionDeletion: false,
        supportsModelSwitch: true,
        supportsApproval: true,
        supportsQueue: true,
        supportsHistoryPaging: true,
      );

  @override
  Stream<ConnectionState> get connectionStates => _stateController.stream;

  @override
  ConnectionState get connectionState => _state;

  @override
  void reconnect() {
    if (_closed) return;
    _setState(ConnectionState.reconnecting);
    // The transport itself manages its own reconnect; we just surface the
    // state change so the UI can show a syncing indicator.
    _setState(ConnectionState.connected);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    _requireOpen();
    final result = await _transport.request('aiVault.listSessions', {
      'limit': 500,
    });
    final sessions = (result['sessions'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(ConversationSummary.fromRow)
        .toList();
    return sessions;
  }

  @override
  Future<OpenConversation> openConversation(String sessionId) async {
    _requireOpen();
    _setState(ConnectionState.connected);
    final historyResult = await _transport.request('agentSession.history', {
      'sessionId': sessionId,
      'direction': 'tail',
      'limit': 100,
    });
    // The host's `agentSession.history` returns the HistoryPage directly
    // (not a mutation wrapper).
    final history = HistoryPage.fromResult(historyResult);
    if (history.fence != null) _fences[sessionId] = history.fence!;
    final recovery = SessionRecovery();
    recovery.seed(history.items, fence: history.fence);
    final eventController = StreamController<SubscribeEvent>();
    final sub = _transport.subscribe(sessionId).listen(
      (frame) {
        if (_closed || eventController.isClosed) return;
        final event = SubscribeEvent.fromFrame(frame);
        if (event.fence != null) _fences[sessionId] = event.fence!;
        recovery.process(event);
        eventController.add(event);
        if (event.type == SubscribeEventType.end) eventController.close();
      },
      onError: (Object error) {
        if (!_closed && !eventController.isClosed) eventController.close();
      },
      onDone: () {
        if (!_closed && !eventController.isClosed) eventController.close();
      },
    );
    _connections[sessionId] = sub;
    return OpenConversation(
      history: history,
      eventController: eventController,
      recovery: recovery,
      onPageBack: (cursor) async {
        final page = await _transport.request('agentSession.history', {
          'sessionId': sessionId,
          'direction': 'before',
          'cursor': cursor.toJson(),
          'limit': 100,
        });
        return HistoryPage.fromResult(page['result'] as Map<String, dynamic>);
      },
    );
  }

  @override
  Future<CreatedSession> createSession(
      {required String agent, required String worktree, String? firstMessage}) async {
    _requireOpen();
    final sessionId = newClientId();
    final request = createSessionRequest(
      sessionId: sessionId,
      worktree: worktree,
      agent: agent,
      firstMessage: firstMessage,
    );
    final result = _unwrapMutation(await _transport.request('agentSession.create', request));
    final fence = result['fence'] as int;
    _fences[sessionId] = fence;
    final value = result['value'] as Map<String, dynamic>;
    final unconfirmedRaw = value['unconfirmedClientMessageIds'];
    return CreatedSession(
      sessionId: value['sessionId'] as String? ?? sessionId,
      fence: fence,
      unconfirmedClientMessageIds: unconfirmedRaw is List
          ? unconfirmedRaw.cast<String>()
          : const [],
    );
  }

  @override
  Future<SendReceipt> send(String sessionId, String text) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = sendSessionRequest(sessionId: sessionId, text: text, fence: fence);
    final result = _unwrapMutation(await _transport.request('agentSession.send', request));
    final newFence = result['fence'] as int? ?? fence;
    _fences[sessionId] = newFence;
    final value = result['value'] as Map<String, dynamic>;
    final queued = value['queued'] is Map<String, dynamic>;
    return SendReceipt(
      clientMessageId: value['clientMessageId'] as String? ?? '',
      fence: newFence,
      queued: queued,
      queuePosition: queued ? (value['queued'] as Map<String, dynamic>)['position'] as int? : null,
      queueState: queued
          ? (value['queued'] as Map<String, dynamic>)['state'] as String?
          : null,
    );
  }

  @override
  Future<void> cancel(String sessionId) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.cancel', sessionId, fence, {});
    await _unwrapMutation(await _transport.request('agentSession.cancel', request));
  }

  @override
  Future<QueueReceipt> deleteQueued(String sessionId, String messageId) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.queuedMessageDelete', sessionId, fence, {'messageId': messageId});
    final result = _unwrapMutation(await _transport.request('agentSession.queuedMessageDelete', request));
    return QueueReceipt(
      deleted: result['deleted'] == true,
      messageId: messageId,
      disposition: result['disposition'] as String?,
    );
  }

  @override
  Future<void> moveQueued(String sessionId, String messageId,
      {String? beforeMessageId, String? afterMessageId}) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.queuedMessageMove', sessionId, fence, {
      'messageId': messageId,
      if (beforeMessageId != null) 'beforeMessageId': beforeMessageId,
      if (afterMessageId != null) 'afterMessageId': afterMessageId,
    });
    await _unwrapMutation(await _transport.request('agentSession.queuedMessageMove', request));
  }

  @override
  Future<void> updateQueued(String sessionId, String messageId, String text,
      {required String expectedBodyFingerprint}) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.queuedMessageUpdate', sessionId, fence, {
      'messageId': messageId,
      'text': text,
      'expectedBodyFingerprint': expectedBodyFingerprint,
    });
    await _unwrapMutation(await _transport.request('agentSession.queuedMessageUpdate', request));
  }

  @override
  Future<void> resumeQueue(String sessionId) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.queuedMessagesResume', sessionId, fence, {});
    await _unwrapMutation(await _transport.request('agentSession.queuedMessagesResume', request));
  }

  @override
  Future<void> respondToApproval(String sessionId, String itemId, int expectedRevision, String optionId) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.respondToApproval', sessionId, fence, {
      'itemId': itemId,
      'expectedRevision': expectedRevision,
      'optionId': optionId,
    });
    await _unwrapMutation(await _transport.request('agentSession.respondToApproval', request));
  }

  @override
  Future<void> respondToQuestion(String sessionId, String itemId, int expectedRevision, List<QuestionAnswer> answers) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.respondToQuestion', sessionId, fence, {
      'itemId': itemId,
      'expectedRevision': expectedRevision,
      'answers': answers
          .map((a) => {
                'questionId': a.questionId,
                'optionIds': a.optionIds,
                if (a.other != null) 'other': a.other,
              })
          .toList(),
    });
    await _unwrapMutation(await _transport.request('agentSession.respondToQuestion', request));
  }

  @override
  Future<ModelCatalog> modelCatalog({required String agent}) async {
    _requireOpen();
    final result = await _transport.request('agentSession.modelCatalog', {
      'agent': agent,
    });
    return ModelCatalog.fromResult(result);
  }

  @override
  Future<SetOptionResult> setModel(String sessionId, String key, String value) async {
    _requireOpen();
    final fence = _requireFence(sessionId);
    final request = _mutation('agentSession.setOption', sessionId, fence, {'key': key, 'value': value});
    final result = _unwrapMutation(await _transport.request('agentSession.setOption', request));
    final options = <String, String>{
      for (final entry in (result['options'] as Map? ?? const <Object?, Object?>{}).entries)
        '${entry.key}': '${entry.value}',
    };
    return SetOptionResult(key: key, value: value, options: options);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _setState(ConnectionState.closed);
    for (final sub in _connections.values) {
      await sub.cancel();
    }
    _connections.clear();
    await _transport.close();
    await _stateController.close();
  }

  int _requireFence(String sessionId) {
    final fence = _fences[sessionId];
    if (fence == null) {
      throw StateError('Session $sessionId has no recorded runtime fence; '
          'open it or create it first.');
    }
    return fence;
  }

  void _requireOpen() {
    if (_closed) throw StateError('Orca backend is closed');
  }

  Map<String, dynamic> _mutation(
      String method, String sessionId, int fence, Map<String, dynamic> fields) =>
      sessionMutation(
        method: method,
        sessionId: sessionId,
        fields: fields,
        expectedRuntimeFence: fence,
      );

  /// Validates the host's mutation envelope (`ok:true` + `replayed` + `fence`
  /// + `cursor` + `value`) and returns the outer result map. Callers read the
  /// outer `fence` and the inner `value` separately — the wire shape keeps
  /// them apart, so a helper that collapses them loses the fence.
  Map<String, dynamic> _unwrapMutation(Map<String, dynamic> result) {
    if (result['ok'] != true) {
      final refusal =
          (result['refusal'] as Map? ?? result).cast<String, dynamic>();
      throw OrcaRefusalException(refusal);
    }
    return result;
  }
}

/// Thrown when the host refuses a mutation. The refusal map carries the
/// host's `code` and `message` (plus optional `details`).
class OrcaRefusalException implements Exception {
  OrcaRefusalException(this.refusal);
  final Map<String, dynamic> refusal;

  String get code => refusal['code'] as String? ?? 'refused';

  @override
  String toString() => 'OrcaRefusalException: $code '
      '${refusal['message'] as String? ?? ''}';
}

/// Watches network connectivity to drive the reconnect state machine.
/// The UI wires this to its own connectivity provider; a null watcher means
/// the backend does not auto-reconnect on network changes.
abstract class ConnectivityWatcher {
  Future<void> onLost(Future<void> Function() reconnect);
  Future<void> onRestored();
}

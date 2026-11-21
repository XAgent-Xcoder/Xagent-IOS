// Orca mobile-link chat entry (design doc §4/§5.1): the structured chat page for
// an Orca host. Two views: the conversation list (writable structured sessions
// only — read-only history rows are never presented as openable, §3.3) and the
// chat itself. Everything goes through [MobileChatBackend] (via
// orcaBackendProvider), never a faked DshClient. DSH-only entries (terminal,
// subagent routing, mux generation ownership) are hidden by reading
// [BackendCapabilities], never invented (§3.2).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orca_client/orca_client.dart';

import '../../state/hosts_state.dart';
import '../../state/orca_connection_state.dart';
import '../../state/orca_hosts_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// One rendered message: a role and the text it carries.
class _Turn {
  const _Turn(this.role, this.text);
  final String role;
  final String text;
  bool get isUser => role == 'user';
}

/// The Orca chat screen: 主机 → 目录 → 会话, the third level of §4.
///
/// No conversation open → the writable session list. One open → the chat
/// (messages, input, model menu, stop). Read-only history rows (no
/// `structuredSession`) are excluded from the list: they cannot be continued
/// through `agentSession.*` (§3.3).
class OrcaChatScreen extends ConsumerStatefulWidget {
  const OrcaChatScreen({super.key, required this.host});

  final HostRef host;

  @override
  ConsumerState<OrcaChatScreen> createState() => _OrcaChatScreenState();
}

class _OrcaChatScreenState extends ConsumerState<OrcaChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  OpenConversation? _open;
  StreamSubscription<SubscribeEvent>? _sub;
  List<_Turn> _turns = const [];
  List<ConversationSummary> _rows = const [];
  String? _openSessionId;
  String _openAgent = 'dsh';
  List<ModelOption> _models = const [];
  bool _sending = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrollBottom);
    unawaited(_loadRows());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _open?.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<MobileChatBackend?> _backend() async {
    return ref
        .read(orcaBackendProvider(widget.host))
        .maybeWhen(data: (v) => v, orElse: () => null);
  }

  void _scrollBottom() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 40) {
      _scroll.animateTo(0, duration: AppMotion.of(context, AppMotion.quick), curve: AppMotion.std);
    }
  }

  /// §4 第三级: the writable structured sessions. No worktree.watch on the
  /// host (verified absent) — a fresh list on open and after each send is the
  /// whole refresh mechanism; no pretend continuous watching.
  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final backend = await _backend();
      if (backend == null || !mounted) return;
      final rows = await backend.listConversations();
      if (!mounted) return;
      setState(() => _rows = rows.where((r) => r.isWritable).toList());
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens an existing writable session (structured ID) and starts streaming.
  Future<void> _openRow(ConversationSummary row) async {
    final sid = row.structuredSessionId;
    if (sid == null) return; // read-only: not offered for opening
    _openSessionId = sid;
    _openAgent = row.agent;
    _turns = const [];
    await _attach(sid, agent: row.agent);
  }

  /// New chat: create with the first message queued (§5.2 create/send 分离 —
  /// the host dispatches firstMessage itself; re-sending it would be a
  /// duplicate submission).
  Future<void> _startChat(String text) async {
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final backend = await _backend();
      if (backend == null || !mounted) return;
      final worktree = ref.read(orcaHostsProvider).orcaById(widget.host.id)?.workingDirectory ?? '/';
      final created = await backend.createSession(agent: 'dsh', worktree: worktree, firstMessage: text);
      _openSessionId = created.sessionId;
      _openAgent = 'dsh';
      _append(_Turn('user', text));
      await _attach(created.sessionId);
      unawaited(_loadRows());
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Continuation: send only, never re-create (§5.2).
  Future<void> _send(String text) async {
    final sid = _openSessionId;
    if (sid == null || text.isEmpty) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final backend = await _backend();
      if (backend == null || !mounted) return;
      final receipt = await backend.send(sid, text);
      _append(_Turn('user', receipt.queued ? '$text  ·（已排队）' : text));
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Attaches to a session: history first, then the live subscription. The
  /// recovery state machine folds every frame (dedupe by itemId, snapshot
  /// overwrite, dispatch states) and re-attaches on a fence jump (§5.6).
  Future<void> _attach(String sessionId, {String agent = 'dsh'}) async {
    final backend = await _backend();
    if (backend == null || !mounted) return;
    await _sub?.cancel();
    await _open?.dispose();
    _error = null;
    final open = await backend.openConversation(sessionId);
    if (!mounted) return;
    _open = open;
    _turns = open.history.items.map((i) => _Turn(i.role, i.text)).toList();
    open.recovery.onReattach = (fence) {
      backend.reconnect();
      if (_openSessionId != null) unawaited(_attach(_openSessionId!));
    };
    _sub = open.events.listen(
      (event) {
        switch (event.type) {
          case SubscribeEventType.snapshot:
          case SubscribeEventType.reset:
            setState(() => _turns = event.items.map((i) => _Turn(i.role, i.text)).toList());
          case SubscribeEventType.batch:
            _fold(event.items);
          case SubscribeEventType.end:
            _scrollBottom();
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
    _openAgent = agent;
    unawaited(_loadModels());
    _scrollBottom();
  }

  void _fold(List<HistoryItem> items) {
    if (items.isEmpty) return;
    setState(() {
      for (final item in items) {
        _turns = [..._turns, _Turn(item.role, item.text)];
      }
    });
  }

  void _append(_Turn turn) {
    setState(() => _turns = [..._turns, turn]);
    _scrollBottom();
  }

  /// §5.5: read the host's actual model catalog for the session's agent; the
  /// menu shows what the host reports, never a built-in list.
  Future<void> _loadModels() async {
    final backend = await _backend();
    if (backend == null || !mounted) return;
    try {
      final catalog = await backend.modelCatalog(agent: _openAgent);
      if (!mounted) return;
      setState(() => _models = catalog.models);
    } on Object {
      if (mounted) setState(() => _models = const []);
    }
  }

  /// §5.5: switch and sync to the host's read-back — not a local-only flip.
  Future<void> _selectModel(String key) async {
    final sid = _openSessionId;
    if (sid == null) return;
    final backend = await _backend();
    if (backend == null || !mounted) return;
    try {
      await backend.setModel(sid, key, key);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    final sid = _openSessionId;
    if (sid == null) return;
    final backend = await _backend();
    if (backend == null) return;
    try {
      await backend.cancel(sid);
      if (mounted) setState(() => _error = null);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _title() => ref.read(orcaHostsProvider).orcaById(widget.host.id)?.name ?? 'Orca';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = ref
        .read(orcaBackendProvider(widget.host))
        .maybeWhen(
            data: (v) => v?.capabilities, orElse: () => null) ??
        const BackendCapabilities();
    final hasOpen = _openSessionId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (hasOpen && caps.supportsModelSwitch)
            PopupMenuButton<String>(
              key: const ValueKey('orca-model'),
              icon: Icon(AppIcons.model, size: 20),
              onSelected: _selectModel,
              itemBuilder: (context) => [
                for (final m in _models)
                  PopupMenuItem(value: m.key, child: Text(m.label)),
              ],
            ),
          if (hasOpen)
            IconButton(
              key: const ValueKey('orca-stop'),
              tooltip: '停止',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _sending ? _stop : null,
            ),
          IconButton(
            key: const ValueKey('orca-back'),
            tooltip: '会话列表',
            icon: const Icon(Icons.list),
            onPressed: () async {
              await _sub?.cancel();
              await _open?.dispose();
              _open = null;
              _sub = null;
              _openSessionId = null;
              _turns = const [];
              unawaited(_loadRows());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: hasOpen ? _chatView(theme) : _listView(theme),
      ),
    );
  }

  /// 会话列表 (§4 第三级): writable structured sessions only.
  Widget _listView(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: _loading && _rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? Center(
                      child: Text('没有可继续的会话 — 发第一条消息开始',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final row = _rows[i];
                        return Card(
                          child: InkWell(
                            onTap: () => unawaited(_openRow(row)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.title ?? row.structuredSessionId ?? row.nativeSessionId,
                                      style: theme.textTheme.bodyLarge),
                                  Text(
                                      '${row.agent} · ${row.messageCount} 条 · ${row.branch ?? row.cwd ?? ''}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(_error!, style: theme.textTheme.labelSmall?.copyWith(color: scheme.error)),
          ),
        _inputBar(theme),
      ],
    );
  }

  /// 聊天: messages + input + queue notice.
  Widget _chatView(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _turns.length,
            itemBuilder: (context, i) => _bubble(theme, _turns[_turns.length - 1 - i]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(_error!, style: theme.textTheme.labelSmall?.copyWith(color: scheme.error)),
          ),
        _inputBar(theme),
      ],
    );
  }

  Widget _inputBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('orca-input'),
              controller: _input,
              decoration: const InputDecoration(hintText: '消息'),
              onSubmitted: _openSessionId == null ? _startChat : _send,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('orca-send'),
            onPressed: _sending
                ? null
                : () => _openSessionId == null ? _startChat(_input.text.trim()) : _send(_input.text.trim()),
            child: _sending
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发送'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, _Turn turn) {
    final scheme = theme.colorScheme;
    final mine = turn.isUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: ShapeDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          shape: Squircle.border(AppShape.md),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          turn.text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: mine ? scheme.onPrimary : scheme.onSurface),
        ),
      ),
    );
  }
}

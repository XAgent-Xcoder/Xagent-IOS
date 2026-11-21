/// Conversation summary parsed from an `aiVault.listSessions` row.
///
/// Three-layer session identity (§3.3 of the design doc):
/// - [agent] — the harness identity (always present).
/// - [nativeSessionId] — the provider-native session ID (always present).
/// - [structuredSessionId] — the Orca-managed structured session ID (optional;
///   only present when the host negotiates the `structuredSession` capability).
///
/// A row without `structuredSession` is a read-only history record: it cannot
/// be continued, approved, or model-switched through `agentSession.*`.
class ConversationSummary {
  const ConversationSummary({
    required this.agent,
    required this.nativeSessionId,
    required this.isWritable,
    this.structuredSessionId,
    this.workspaceId,
    this.title,
    this.cwd,
    this.branch,
    this.model,
    this.messageCount = 0,
    this.queuedMessageCount = 0,
    this.subagentTranscriptCount = 0,
    this.updatedAtMs,
  });

  /// Harness agent identifier (e.g. `claude`, `codex`, `dsh`).
  final String agent;

  /// Provider-native session ID (the `sessionId` field on the row).
  final String nativeSessionId;

  /// The Orca structured session ID, when present. `null` means the row is a
  /// pure history record with no Orca-managed structured owner.
  final String? structuredSessionId;

  /// The workspace ID the structured session belongs to, when present.
  final String? workspaceId;

  /// Whether the conversation can be continued through `agentSession.*`.
  /// `true` only when [structuredSessionId] is non-null.
  final bool isWritable;

  /// Display title (may be blank/empty for cold rows; the client may read
  /// `projections` separately to fill a title).
  final String? title;

  /// Working directory (absolute path) or null.
  final String? cwd;

  /// Git branch name or null.
  final String? branch;

  /// Model identifier in use, or null when unknown.
  final String? model;

  /// Message count on the row.
  final int messageCount;

  /// Queued message count on the row.
  final int queuedMessageCount;

  /// Subagent transcript count on the row.
  final int subagentTranscriptCount;

  /// Last update timestamp in milliseconds, when the row carries one.
  final int? updatedAtMs;

  /// Parses a raw `aiVault.listSessions` row (the `AiVaultSession` wire object).
  factory ConversationSummary.fromRow(Map<String, dynamic> row) {
    final structured = row['structuredSession'] is Map<String, dynamic>
        ? row['structuredSession'] as Map<String, dynamic>
        : null;
    final structuredSessionId =
        structured != null && structured['sessionId'] is String
            ? structured['sessionId'] as String
            : null;
    return ConversationSummary(
      agent: row['agent'] is String ? row['agent'] as String : 'unknown',
      nativeSessionId: row['sessionId'] is String ? row['sessionId'] as String : '',
      structuredSessionId: structuredSessionId,
      workspaceId:
          structured != null && structured['workspaceId'] is String
              ? structured['workspaceId'] as String
              : null,
      isWritable: structuredSessionId != null,
      title: row['title'] is String ? row['title'] as String : null,
      cwd: row['cwd'] is String ? row['cwd'] as String : null,
      branch: row['branch'] is String ? row['branch'] as String : null,
      model: row['model'] is String ? row['model'] as String : null,
      messageCount: row['messageCount'] is int ? row['messageCount'] as int : 0,
      queuedMessageCount: row['queuedMessageCount'] is int
          ? row['queuedMessageCount'] as int
          : 0,
      subagentTranscriptCount: row['subagentTranscriptCount'] is int
          ? row['subagentTranscriptCount'] as int
          : 0,
      updatedAtMs: row['updatedAt'] is int ? row['updatedAt'] as int : null,
    );
  }
}

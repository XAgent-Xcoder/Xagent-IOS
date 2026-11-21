/// The RPC transport a [MobileChatBackend] implementation talks to.
///
/// [LegacyOrcaClient] implements this; tests substitute a fake so a backend
/// can be exercised without a live WebSocket.
abstract class OrcaRpcTransport {
  /// A single unary RPC. Returns the host's `result` object; throws an
  /// [OrcaRequestException] when the host refuses.
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Subscribes to a session's live event stream. Returns frames
  /// (`snapshot` / `batch` / `reset` / `end`).
  Stream<Map<String, dynamic>> subscribe(
    String sessionId, {
    Map<String, dynamic>? cursor,
  });

  /// Closes the transport.
  Future<void> close();
}

import 'package:orca_client/orca_client.dart';
import 'package:test/test.dart';

void main() {
  test('operation id has the host-required shape', () {
    final id = newOperationId();
    expect(RegExp(r'^\d{13}-[0-9a-f]{32}$').hasMatch(id), isTrue);
  });

  test('payload fingerprint is stable and collision-sensitive', () {
    final a = sessionPayloadFingerprint('agentSession.send', 's1', {'body': 'x'});
    final b = sessionPayloadFingerprint('agentSession.send', 's1', {'body': 'x'});
    final c = sessionPayloadFingerprint('agentSession.send', 's1', {'body': 'y'});
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a, isNot(equals(sessionPayloadFingerprint('agentSession.create', 's1', {'body': 'x'}))));
  });

  test('create mutation carries a null fence, send carries the host fence', () {
    final created = createSessionRequest(sessionId: 's', worktree: 'wt', agent: 'dsh');
    expect(created['envelope']['expectedRuntimeFence'], isNull);
    expect(created['envelope']['payloadFingerprint'], isNotEmpty);
    final sent = sendSessionRequest(sessionId: 's', text: 'hi', fence: 7);
    expect(sent['envelope']['expectedRuntimeFence'], equals(7));
    expect(sent['body']['blocks'], isA<List>());
  });
}

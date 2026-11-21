// iOS 远程客户端：远程任务完成时，App 通过 dsh/notify 通道发本地通知。
// Dart 侧契约：status 返回 native=true（iOS 有原生侧），tryShow 走 status→show
// 两步，且 show 收到完整的 NotifyPost 载荷。原生侧真实现（UNUserNotificationCenter）
// 在 Swift（DshGoChannels.wireNotify），真机验证另行标注；这里只钉 Dart→native
// 的调用序列与入参形状，确保 iOS 上通道已注册、调用不抛 MissingPluginException。
//
//   flutter test test/ios_notify_contract_test.dart

import 'package:dsh_app/notify/notify_channel.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dsh/notify');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const post = NotifyPost(
    group: 'ssh:lab|s1',
    key: 'turn-1',
    attention: true,
    title: 'AgentPort',
    text: '任务完成',
    publicText: '任务结束',
    sessionId: 's1',
    host: HostRef.ssh('lab'),
    kind: 'turn',
  );
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) reply;

  setUp(() {
    calls.clear();
    // iOS 原生侧存在：status 返回 native 全开。
    reply = (call) async =>
        call.method == 'status' ? {'native': true, 'enabled': true, 'done': true, 'attention': true} : null;
    messenger.setMockMethodCallHandler(methods, (call) {
      calls.add(call);
      return reply(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test('iOS 上 tryShow 走 status→show 且 show 带完整载荷', () async {
    expect(await NotifyChannel().tryShow(post), isTrue);
    expect(calls.map((c) => c.method), ['status', 'show']);
    final showArgs = calls.last.arguments as Map;
    expect(showArgs['group'], 'ssh:lab|s1');
    expect(showArgs['key'], 'turn-1');
    expect(showArgs['title'], 'AgentPort');
    expect(showArgs['sessionId'], 's1');
  });

  test('status 报原生可用时 show 不被拦截', () async {
    expect((await NotifyChannel().status()).native, isTrue);
    expect(await NotifyChannel().tryShow(post), isTrue);
  });
}

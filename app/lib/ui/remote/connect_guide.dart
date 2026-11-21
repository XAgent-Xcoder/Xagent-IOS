import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common/empty_view.dart';
import 'remote_screen.dart';

/// iOS 远程客户端的"未选择主机"引导：主机为 local（未选择/回落到默认值）时
/// 抽屉与网页首页共用的空状态。点「连接电脑或服务器」进远程页（添加/登录/配对），
/// 不强制扫码。Android 不走这里（本地引擎有自己的空状态）。
class ConnectGuideView extends StatelessWidget {
  const ConnectGuideView({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyView(
      compact: compact,
      title: l10n.hostUnselected,
      message: l10n.remoteHostsIntro,
      actionLabel: l10n.remoteConnectComputer,
      onAction: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RemoteScreen()))),
    );
  }
}

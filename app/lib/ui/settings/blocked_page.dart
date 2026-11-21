import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../shell/page_frame.dart';

/// 被能力门禁拦下的设置页占位（iOS 本地引擎/手机操控页经直接路由打开时）。
/// 链接路径（pageForId/settingsPageForLink）对被禁 id 返回 null 走 LinkRouter
/// 既有"无法打开链接"兜底；本页兜住搜索直达、spot 聚焦等 settingsPage() 调用。
/// 走 AppPage 框：被推路由也有返回出口，不把用户困死（CLAUDE.md：拒绝之后
/// 用户要走得回来）。
class BlockedFeaturePage extends StatelessWidget {
  const BlockedFeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.l10n.iosFeatureUnavailable,
      showLargeTitle: false,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text(context.l10n.iosFeatureUnavailable)),
        ),
      ],
    );
  }
}

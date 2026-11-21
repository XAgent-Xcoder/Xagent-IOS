import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/hosts_state.dart';
import '../common/app_dialog.dart';
import '../common/overview_card.dart';
import '../common/status_chip.dart';
import '../remote/host_status.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// xcodex 账号二级页：账号卡 + 已配对主机列表 + 登出 + API 占位（预留）。
class RelayAccountPage extends ConsumerWidget {
  const RelayAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(relayAccountProvider);
    final account = async.value ?? const RelayAccountState();

    return AppPage.list(
      title: l10n.remoteXcodexAccountTitle,
      children: [
        AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.standard),
          switchInCurve: AppMotion.std,
          switchOutCurve: AppMotion.std,
          layoutBuilder: (current, previous) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...previous, ?current]),
          child: _switch(context, ref, account, async),
        ),
      ],
    );
  }

  Widget _switch(BuildContext context, WidgetRef ref, RelayAccountState account, AsyncValue<RelayAccountState> async) {
    if (account.loggingIn) return _SigningIn(key: const ValueKey('signing-in'), account: account);
    if (!account.signedIn) return _SignIn(key: const ValueKey('sign-in'), account: account, async: async);
    return _SignedIn(key: const ValueKey('signed-in'), account: account);
  }
}

/// 未登录：账号介绍卡 + xcodex 登录按钮 + 错误文案。
class _SignIn extends ConsumerWidget {
  const _SignIn({super.key, required this.account, required this.async});
  final RelayAccountState account;
  final AsyncValue<RelayAccountState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final notifier = ref.read(relayAccountProvider.notifier);
    final available = ref.watch(relayBackendProvider).available;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GlassSurface(
        borderRadius: AppShape.radiusLg,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SettingsIcon(AppIcons.lock, tint: 1),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.remoteRelaySignInTitle, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(l10n.remoteRelaySignInHelp, style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: available && !async.isLoading ? () => unawaited(notifier.startDeviceLogin()) : null,
                icon: const Icon(AppIcons.lock, size: 18),
                label: Text(l10n.remoteXcodexSignInTitle),
              ),
              const SizedBox(height: 8),
              Text(l10n.remoteXcodexSignInHelp, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary)),
              if (account.error case final e?) ...[const SizedBox(height: 10), Text(e, style: theme.textTheme.bodySmall?.copyWith(color: colors.danger))],
            ],
          ),
        ),
      ),
    );
  }
}

/// 登录中：旋转等待 + 取消 + 复制登录链接。
class _SigningIn extends ConsumerWidget {
  const _SigningIn({super.key, required this.account});
  final RelayAccountState account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final notifier = ref.read(relayAccountProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GlassSurface(
        borderRadius: AppShape.radiusLg,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.remoteBrowserSignInPending, style: theme.textTheme.bodyMedium)),
                  TextButton(onPressed: notifier.cancelLogin, child: Text(l10n.commonCancel)),
                ],
              ),
              if (account.loginUrl case final u?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: colors.textTertiary, padding: EdgeInsets.zero),
                    onPressed: () => Clipboard.setData(ClipboardData(text: u.toString())),
                    icon: const Icon(AppIcons.copy, size: 15),
                    label: Text(l10n.remoteCopySignInLink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已登录：账号卡（OverviewCard）+ 已配对主机列表 + 登出。
class _SignedIn extends ConsumerWidget {
  const _SignedIn({super.key, required this.account});
  final RelayAccountState account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(relayAccountProvider.notifier);
    final user = account.user!;
    final providerName = user.provider != null ? _providerName(user.provider!) : '';

    final hostsChildren = <Widget>[
      if (account.hosts.isEmpty && account.hostsFailed)
        SettingsTile(
          icon: AppIcons.refresh,
          tinted: false,
          title: l10n.remoteErrHostsRetry,
          onTap: () => unawaited(notifier.refresh()),
        )
      else if (account.hosts.isEmpty)
        SettingsTile(icon: AppIcons.computer, tinted: false, title: l10n.remoteNoHosts, subtitle: l10n.remoteRelaySetupHelp)
      else
        for (final h in account.hosts) _HostRow(host: h),
      SettingsTile(
        icon: AppIcons.logout,
        tinted: false,
        danger: true,
        title: l10n.commonSignOut,
        onTap: () => _confirmLogout(context, notifier),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewCard(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          leading: const OverviewGlyph(AppIcons.account, tint: 0),
          title: Text(user.displayName),
          subtitle: Text([providerName, account.server].where((s) => s.isNotEmpty).join(' · ')),
          semanticLabel: l10n.hubSettingsAccountSemantics(user.displayName, ''),
        ),
        SettingsSection(title: l10n.commonRemoteHost, children: hostsChildren),
        // API 部分预留：将来卖 API 时在这里加一个 SettingsSection('API', ...)。
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context, RelayAccountController notifier) async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.remoteRelaySignOutTitle),
        content: Text(l10n.remoteRelaySignOutBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(l10n.remoteSignOut)),
        ],
      ),
    );
    if (ok == true) await notifier.logout();
  }
}

/// 已配对主机行：在线点 + 主机名 + 平台/Harness 副 + 在线/离线状态。
class _HostRow extends StatelessWidget {
  const _HostRow({required this.host});
  final RelayHost host;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = DshColors.of(context);
    final online = host.online;
    return SettingsTile(
      icon: hostKindIcon(HostKind.relay),
      tinted: false,
      title: host.name,
      subtitle: host.subtitle,
      value: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedStatusDot(tone: online ? StatusTone.ok : StatusTone.idle, size: 6),
          const SizedBox(width: 6),
          Text(online ? l10n.remoteOnline : l10n.remoteOffline,
              style: TextStyle(color: online ? colors.success : colors.textTertiary)),
        ],
      ),
      chevron: false,
    );
  }
}

String _providerName(String p) => switch (p) {
  'github' => 'GitHub',
  'zhihu' => appL10n.brandZhihu,
  'google' => 'Google',
  'password' => appL10n.remoteEmail,
  'xcodex-device' => appL10n.remoteEmail,
  _ => p,
};

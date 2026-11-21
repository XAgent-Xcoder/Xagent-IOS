# RelayAccountCard（设置概览卡改 xcodex）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 设置页顶部概览卡从「登录 DeepSeek 账号 / 或填写 API Key」改成 xcodex 账号入口，登录后进入一个只显示账号与已配对远程主机（电脑）的二级页，并为以后的 API 区块预留位置。

**Architecture:** 概览卡 `SettingsOverview` 从 watch `accountProvider`/`balanceProvider`/`accountWalletBalanceProvider` 改为只 watch `relayAccountProvider`，三态：未登录→「登录 xcodex 账号」、登录中→「正在登录 xcodex 账号」、已登录→「已登录 · 主机名 · 在线」，三态点击都进新的 `RelayAccountPage`；`remoteOnly`（纯远程主机、本机无引擎）分支原样保留给 Android。新二级页 `RelayAccountPage` 未登录态复用 `startDeviceLogin()`（浏览器授权+轮询，不扫码），已登录态显示账号信息、已配对主机列表、登出，并留一个空的 API 区块占位。DeepSeek 的 `AccountPage`/`accountProvider`/`balanceProvider` 不动（第二步再删）。

**Tech Stack:** Flutter 3.13.5+, Riverpod, l10n (`flutter gen-l10n`, 源 `lib/l10n/app_zh.arb`/`app_en.arb`，生成物 `lib/l10n/gen/`)。测试 `flutter test`。

**Spec:** docs/superpowers/specs/2026-11-19-relay-account-card-design.md

## Global Constraints

- iOS-only 生产构建；Android 的 `localEngineSupportedProvider==true` 代码路径不得破坏。
- 新文案必须中英文同时加到两个 .arb 源文件，并跑 `flutter gen-l10n` 更新 `gen/`。
- 新二级页路径 `app/lib/ui/account/relay_account_page.dart`，类名 `RelayAccountPage`，`const` 构造。
- 登录复用 `relayAccountProvider.notifier.startDeviceLogin()` / `.cancelLogin()` / `.logout()`，不新写登录逻辑。
- 概览卡 `SettingsOverview` 的 `remoteOnly` 分支（`runtime.status.runtimeMissing && !active.isLocal`）保留：它属于 Android 远程主机场景，iOS 上该分支不可达。

## Review Focus

- **概览卡三态切换**：relay `signedIn` 翻转时卡片文案、语义标签要随之切换；`hostLink != null` 时点 RemoteScreen，否则点 RelayAccountPage（不能点错页）。
- **概览卡语义标签**：hostLink 非空时用 `hubSettingsHostSemantics(title, hostLink)`，否则用 `hubSettingsAccountSemantics(title, subtitle)`；三态都要走对。
- **RelayAccountPage 登录中**：`loggingIn==true` 时显示等待条 + 可复制登录 URL + 取消，不显示登录按钮。
- **RelayAccountPage 登出**：登出后 `hosts` 清空、`user` 变 null，卡片回到登录态；登出要确认对话框。
- **已配对主机列表的空态**：`hosts.isEmpty && hostsFailed` → 重试；`hosts.isEmpty` → 引导去电脑端；有主机 → 逐行显示在线点 + 平台 + Harness 版本。

---

### Task 1: 概览卡切到 xcodex，三态进 RelayAccountPage

**Files:**
- Modify: `app/lib/ui/settings/settings_screen.dart:384-479`
- Modify: `app/lib/l10n/app_zh.arb`、`app/lib/l10n/app_en.arb`（新增 `hubSettingsXcodexSignIn`、`hubSettingsXcodexSigningIn`、`hubSettingsXcodexSignedIn` 三组）
- Test: `app/test/settings/settings_overview_xcodex_test.dart`（新）
- 更新：`app/test/settings/settings_overview_remote_test.dart`（「still on 本机: sign-in as before」那条的断言文案要改）

**Interfaces:**
- Consumes: `relayAccountProvider`（`app/lib/state/hosts_state.dart:749`，`RelayAccountState.signedIn`/`user`/`loggingIn`）、`localEngineSupportedProvider`（`app/lib/state/platform_state.dart:16`）、`SettingsIndex.entry(SettingsPageId.account)`（`app/lib/ui/settings/index/settings_pages.dart:113`）。
- Produces: 概览卡三态文案常量 `l10n.hubSettingsXcodexSignIn`（中文「登录 xcodex 账号」/ 英文 "Sign in with xcodex"）、`l10n.hubSettingsXcodexSigningIn`（中文「正在登录 xcodex 账号」/ 英文 "Signing in…"）、`l10n.hubSettingsXcodexSignedIn(hostName, onlineLabel)`（中文「已登录 · {host} · {online}」/ 英文 "Signed in · {host} · {online}"）；点击一律进 `RelayAccountPage`（hostLink 分支除外）。

- [ ] **Step 1: 写失败测试 `settings_overview_xcodex_test.dart`**

仿 `settings_overview_remote_test.dart` 的骨架，`_overrides` 里把 `accountProvider` 那条 override 换掉，加 `relayAccountProvider.overrideWith(...)`，断言三态：
1. relay `signedIn==false`（`RelayAccountState()`）→ 卡上出现「登录 xcodex 账号」、不出现「登录 DeepSeek 账号」「或填写 API Key」，语义标签含该文案。
2. relay `loggingIn==true`（`RelayAccountState(loggingIn: true, loginUrl: Uri.https('agent.xcodex.vip','login/x'))`）→ 卡上出现「正在登录 xcodex 账号」。
3. relay `signedIn==true`（`RelayAccountState(user: RelayUser(id:'u', displayName:'tester', provider:'password'), hosts: [RelayHost(id:'h1', name:'MacBook', online: true)])`，且 `activeHostProvider` override 为 `HostRef.relay('h1', name:'MacBook')`、`hostLinkStatusProvider` override 为 `Stream.value(HostLinkStatus(HostLinkPhase.connected))`）→ 卡上出现「已登录 · MacBook · 已连接」。

跑：`cd app && flutter test test/settings/settings_overview_xcodex_test.dart -v`
预期：FAIL（概览卡仍显示「登录 DeepSeek 账号」）。

- [ ] **Step 2: 改 SettingsOverview 的 switch**

把 switch 分支从 `account.phase` 改成 relay 三态 + `remoteOnly`：
```
switch:
  remoteOnly 分支 → 原样保留（hostLink 语义）
  case relayAccount.loggingIn → 登录中卡（图标 AppIcons.lock，副 l10n.hubSettingsXcodexSigningIn）
  case relayAccount.signedIn → 已登录卡（头像或 AppIcons.account，副 l10n.hubSettingsXcodexSignedIn(hostName, online)；hostName 取自 `hostNameProvider(active)`，online 取自 `HostStatusView.ofLink(...).label`）
  default → 未登录卡（AppIcons.lock，副 l10n.hubSettingsXcodexSignIn）
```
点击：`onTap: () => _push(hostLink != null ? const RemoteScreen() : const RelayAccountPage())`。
引擎 footer：保留原样（`localEngineSupportedProvider` 为 false 时本就 null）。
去掉 `accountProvider`、`balanceProvider`、`accountWalletBalanceProvider` 的 watch；新增 `ref.watch(relayAccountProvider)`、`ref.watch(hostLinkStatusProvider(active))`。`money`/`balanceLine`/`low`/`mono` 这些只属于 DeepSeek 的变量一并删掉。

- [ ] **Step 3: 加 l10n 三条并 regen**

在 `app_zh.arb` 加 `hubSettingsXcodexSignIn`、`hubSettingsXcodexSigningIn`、`hubSettingsXcodexSignedIn`（带 `{host}`/`{online}` 占位）；`app_en.arb` 对应英文。然后 `cd app && flutter gen-l10n`。

- [ ] **Step 4: 跑新测试**

`cd app && flutter test test/settings/settings_overview_xcodex_test.dart -v`，预期 PASS。

- [ ] **Step 5: 更新 settings_overview_remote_test.dart**

原「no runtime, still on 本机: sign-in as before」那条断言的「登录 DeepSeek 账号」改成「登录 xcodex 账号」，语义标签断言同步改。其它 remoteOnly 三条（实验室服务器、连接失败、API Key saved）不动。

跑：`cd app && flutter test test/settings/settings_overview_remote_test.dart -v`，预期 PASS。

- [ ] **Step 6: Commit**

```
git add app/lib/ui/settings/settings_screen.dart app/lib/l10n/app_zh.arb app/lib/l10n/app_en.arb app/lib/l10n/gen/ app/test/settings/settings_overview_xcodex_test.dart app/test/settings/settings_overview_remote_test.dart
git commit -m "feat(settings): 概览卡切到 xcodex 账号入口"
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

---

### Task 2: 新建 RelayAccountPage 二级页

**Files:**
- Create: `app/lib/ui/account/relay_account_page.dart`
- Test: `app/test/account/relay_account_page_test.dart`（新）

**Interfaces:**
- Consumes: `relayAccountProvider`（`RelayAccountState` 全字段）、`relayAccountProvider.notifier`（`.startDeviceLogin()` / `.cancelLogin()` / `.logout()` / `.refresh()`）、`activeHostProvider`、`hostLinkStatusProvider`、`hostNameProvider`。
- Produces: `RelayAccountPage`（`const` 构造），未登录态显示登录按钮 + 等待条 + 登录 URL 复制 + 取消，已登录态显示账号卡 + 已配对主机列表（每行：在线点 + 主机名 + 平台/Harness 版本 + 状态文案）+ 登出按钮 + 一个空的 `SettingsSection(title: 'API')` 占位（无 children，本期不渲染）。

- [ ] **Step 1: 写失败测试 `relay_account_page_test.dart`**

仿 `settings_overview_remote_test.dart` 的 `_pump` 骨架。四个用例：
1. 未登录 → `find.text('使用 xcodex 账号登录')`（复用 `remoteXcodexSignInTitle`）`findsOneWidget`；`find.text('取消')` `findsNothing`。
2. 登录中（`loggingIn: true, loginUrl: Uri.https('agent.xcodex.vip','login/x')`）→ `find.text('等待浏览器授权')`（`remoteBrowserSignInPending`）`findsOneWidget`；`find.text('取消')` `findsOneWidget`；登录 URL 文案 `findsOneWidget`。
3. 已登录 0 主机（`user` 非空、`hosts: []`）→ 账号名 `findsOneWidget`；`find.text('还没有配对的电脑')`（`remoteNoHosts`）`findsOneWidget`。
4. 已登录 2 主机（`hosts: [RelayHost(id:'h1', name:'MacBook', online: true, platform:'darwin', harnessVersion:'0.2.1-rc.2'), RelayHost(id:'h2', name:'Work PC', online: false, platform:'windows')]`）→ 两行主机名各 `findsOneWidget`；在线/离线状态文案各 `findsOneWidget`。

跑：`cd app && flutter test test/account/relay_account_page_test.dart -v`
预期：FAIL（文件不存在）。

- [ ] **Step 2: 实现 `relay_account_page.dart`**

页面结构（`AppPage.list`，标题 `remoteXcodexAccountTitle`（新 l10n「xcodex 账号」/ "xcodex Account"），`actions: [if signedIn 刷新 IconButton]`）：
- `AnimatedSwitcher` 按 `signedIn` / `loggingIn` / `error` 切三块。
- 未登录块：账号卡（`GlassSurface` + `AppIcons.account` 头像 + 标题 `remoteRelaySignInTitle` + 副 `remoteRelaySignInHelp`）+ 登录按钮（`FilledButton.icon`，`onPressed: () => notifier.startDeviceLogin()`，文案 `remoteXcodexSignInTitle` + 帮助 `remoteXcodexSignInHelp`）+ 错误态 `Text(e, color: danger)`。
- 登录中块：等待行（旋转 `CircularProgressIndicator` + `remoteBrowserSignInPending` + 取消 `TextButton`）+ 登录 URL 复制按钮（`TextButton.icon`，`onPressed` 写 `Clipboard`）。
- 已登录块：账号卡（`OverviewCard`，头像 `AppIcons.account`，标题 `user.displayName`，副 `[providerName, server].join(' · ')`）+ 已配对主机 `SettingsSection`（空态：`hostsFailed` → 「重试拉取」tile + `notifier.refresh()`；空 → `remoteNoHosts` + `remoteRelaySetupHelp`；有 → 逐行 `_HostRow`：在线点 + 主机名 + `RelayHost.subtitle` + 状态）+ API 占位 `SettingsSection(title: 'API', children: [])`（本期空不渲染）+ 登出 `TextButton.icon`（`onPressed` 先确认对话框再 `notifier.logout()`，文案 `commonSignOut`）。

复用：`OverviewCard`（`app/lib/ui/common/overview_card.dart`）、`AnimatedStatusDot`（`app/lib/ui/common/status_chip.dart`）、`hostKindIcon`/`hostKindTint`（`app/lib/ui/remote/host_status.dart`）。

- [ ] **Step 3: 加 l10n `remoteXcodexAccountTitle`**（zh「xcodex 账号」/ en "xcodex Account"）并 `flutter gen-l10n`。

- [ ] **Step 4: 跑测试** `flutter test test/account/relay_account_page_test.dart -v`，预期 PASS。

- [ ] **Step 5: Commit**

```
git add app/lib/ui/account/relay_account_page.dart app/lib/l10n/app_zh.arb app/lib/l10n/app_en.arb app/lib/l10n/gen/ app/test/account/relay_account_page_test.dart
git commit -m "feat(account): xcodex 账号二级页（账号 + 已配对主机 + API 占位）"
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

---

### Task 3: 概览卡与二级页串起来，整链验证

**Files:**
- Test: `app/test/account/relay_account_page_flow_test.dart`（新）

**Interfaces:**
- Consumes: Task 1 的概览卡点击（进 `RelayAccountPage`）、Task 2 的 `RelayAccountPage` 登录/已登录态。
- Produces: 端到端路径：概览卡「登录 xcodex 账号」→ 点进二级页 → 看到「使用 xcodex 账号登录」按钮。

- [ ] **Step 1: 写失败测试 `relay_account_page_flow_test.dart`**

一个用例：pump `SettingsOverview()`（relay `signedIn==false`）→ 卡上「登录 xcodex 账号」`findsOneWidget` → tap 它 → pump → `find.byType(RelayAccountPage)` `findsOneWidget`，且二级页上「使用 xcodex 账号登录」`findsOneWidget`。

跑：`cd app && flutter test test/account/relay_account_page_flow_test.dart -v`，预期 FAIL（概览卡还没连到二级页——其实 Task 1 已连，此测试是回归锁）。

- [ ] **Step 2: 确认无需改代码，跑测试**，预期 PASS。若 FAIL，回 Task 1 修概览卡的 `_push`。

- [ ] **Step 3: Commit**

```
git add app/test/account/relay_account_page_flow_test.dart
git commit -m "test: 概览卡→xcodex 二级页整链锁"
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

---

## Review Focus → Task 映射

- 概览卡三态切换 → Task 1 Step 1（三态断言）+ Step 2（switch 改写）
- 概览卡语义标签 → Task 1 Step 2（hostLink 三元保留）
- RelayAccountPage 登录中 → Task 2 Step 1 用例 2 + Step 2 登录中块
- RelayAccountPage 登出 → Task 2 Step 2 登出按钮（确认对话框 + `logout()`）
- 已配对主机列表空态 → Task 2 Step 1 用例 3、4 + Step 2 已配对主机 section

## 留给实现者

- `RelayAccountState` 的 `providers` 列表本期不消费（登录只用 `startDeviceLogin`）。
- API 占位 section 的标题文案用硬编码 `'API'` 还是 l10n，以实现时最简洁为准；本期不渲染所以无文案依赖。

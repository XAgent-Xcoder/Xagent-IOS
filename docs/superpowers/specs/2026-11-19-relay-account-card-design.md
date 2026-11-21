# 设置页概览卡改造成 xcodex 中继卡（第一步）

## 意图

xcodex 产品主打手机远程电脑。设置页顶部概览卡现在展示 DeepSeek 账号 / API Key，
不是本产品的核心；xcodex 账号登录（relay device login）才是。本步把入口切到
xcodex，DeepSeek 旧逻辑暂留（iOS 已不可达，第二步清理）。

## 目标

- 概览卡未登录态显示「登录 xcodex 账号」，点击进入二级页。
- 二级页未登录态直接发起 xcodex device login（浏览器授权 + 轮询，不扫码）。
- 二级页已登录态显示账号信息（用户名 / 登录方式 / 服务器）与已配对远程主机
  （电脑）列表：在线状态、平台、Harness 版本；复用 RemoteScreen 的连接/切换逻辑。
- 已登录时概览卡显示「已登录 · 当前主机名（在线状态）」。
- 二级页预留 API 区块位置（以后卖 API 再填，本期空实现不进 UI）。

## 非目标

- 不删 DeepSeek / balance / AccountPage（第二步）。
- 不改动 SSH 主机管理（仍由 RemoteScreen 承载，概览卡不重复）。
- 不改动 chat / 余额横幅。

## 约束

- iOS-only 生产构建；Android 代码路径保留不破坏。
- `RelayAccountController.startDeviceLogin()` 已存在且无本地引擎依赖，直接复用。
- 登录中 / 登录 URL 展示 / 取消，复用 RemoteScreen `_LoginCard` 的模式
  （`RelayAccountState.loggingIn` / `loginUrl`）。

## 方案（Approaches）

1. **新建 RelayAccountPage 二级页 + 概览卡改 watch relayAccountProvider**（选定）
   边界干净；AccountPage 保留原样，Android 路径不动。
2. 改造 AccountPage 成 xcodex 版——需清掉 DeepSeek 钱包/充值/API Key widget，
   与保留旧码的前提矛盾，弃。
3. 二级页复用 RemoteScreen——其 DSH Remote 区与 SSH/设置区混杂，账号语义不纯粹，弃。

## 改动点

- `ui/account/relay_account_page.dart`（新）：账号卡 + 已配对主机列表 + 登出。
- `ui/settings/settings_screen.dart` `SettingsOverview`：watch `relayAccountProvider`
  替代 `accountProvider`/`balanceProvider`/`accountWalletBalanceProvider`；
  未登录 / 登录中 / 已登录三态；点击进 RelayAccountPage；
  保留 remoteOnly 主机态与引擎 footer（Android 仍需要）。
- l10n：新增概览卡「登录 xcodex 账号」等文案（中英文 arborist 源文件）。

## 留给实现者

- 概览卡 remoteOnly 分支（纯远程主机、未登录 relay 的场景）保留原样还是并入
  登录态，以实现时最小改动为准。
- 主机列表行直接抽自 RemoteScreen `_RelayRow` 的呈现（在线点 + 平台/Harness）。

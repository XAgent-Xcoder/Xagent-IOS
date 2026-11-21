# AgentPort iOS 远程客户端 — 设计

日期：2026-11-13
状态：待确认

## 意图与为什么

DSH Go / AgentPort 目前是 Android-only（Flutter UI + Kotlin 原生层在 PRoot 里跑 DSH 引擎）。README 承诺过"尽快适配 iOS"，路线图（`docs/roadmap.md:165`）早已定下 iOS 的形态：**只做远程客户端**，因为 iOS 系统不允许在 App 内运行 Linux 环境（PRoot 方案不可移植）。

本项目把现有 Android 的 Flutter 工程复制为同级新项目，生成 iOS 壳，做成 AgentPort 的 iOS 远程客户端：iOS 手机/平板通过远程连接（配对/中继/LAN）直连电脑上跑的 DSH 主机，复用现有 Dart 全部客户端代码。

## 目标 / 非目标 / 反目标

- 目标：新仓库 `dsh-Go-ios`（`/Users/joseph/projects/dsh-Go-ios`），iOS 版 AgentPort，远程连接电脑完整可用（配对、WebRTC/LAN/TURN/Relay 中继、聊天、会话、设置、l10n、主题），可在 Xcode 里编译出 `.app`。
- 非目标：本地引擎（PRoot）、手机操控（无障碍）、Android 专属的桌面组件/小组件/快捷方式、APK 更新、启动窗口视频——在 iOS 上全部隐藏入口而不是实现。
- 反目标：不做 iOS 上的 proot/容器化引擎（系统禁止）；不把 Kotlin 逐行翻成 Swift（没有转换工具，也没有价值——原生层只保留 iOS 需要的少量通道）；不要求首发版本覆盖 Android 的全部功能项，"远程 + 聊天"能用是底线。

## 约束

- 品牌：沿用 AgentPort（applicationId `com.xcoder.agentport`，中继 `agent.xcodex.vip`）。iOS bundle id 取 `com.xcoder.agentport.ios`（避免与 Android 的 id 混淆，同一 Apple 开发者账号下两平台不冲突）。
- 仓库策略：新仓库是独立 git 仓库（`git init`），不是 dsh-Go 的 worktree 或子目录；`packages/`、`sdk/`、`runtime/`、`tooling/`、`docs/` 不复制——iOS 版只用 `app/` 和 `packages/dsh_client`、`packages/dsh_remote`（纯 Dart）。
- 代码契约：与 dsh-Go 的客户端 wire 契约（plugin 0.6.2 / ds-harness-remote 479b943）保持一致，协议层不动。
- 验证：iOS 代码只能在本机（macOS）用 Xcode 编译验证 + `flutter analyze` + `flutter test`（Dart 层测试，桌面引擎可跑）；真机 iOS 运行未验证，如实标注。

## 方案（已定的取舍）

1. **复制 + 生成 iOS 壳**（选定）：复制 `app/` 和 `packages/`，`flutter create --platforms=ios` 生成 iOS 工程，Dart 代码全量复用。理由：整个 UI 与客户端逻辑都是 Dart，本来就是跨平台的；"转换"只发生在原生层。
2. 逐行 Kotlin→Swift 翻译（否决）：35 个平台通道里绝大多数是 Android 专属（PRoot 运行时、无障碍手机操控、桌面小组件），翻过去也用不上，纯属徒劳。
3. 在 dsh-Go 原仓库内加 `ios/`（否决）：原仓库的 Android 原生层与 iOS 降级逻辑会互相纠缠，且用户要求独立同级项目。

## 做法要点

### 1. 项目骨架

```
/Users/joseph/projects/dsh-Go-ios/
  app/            Flutter App 本体（复制自 dsh-Go/app，去掉 android/）
  packages/       dsh_client、dsh_remote（纯 Dart，原样复制）
  docs/           本设计文档的副本 + iOS 版说明
```

- `flutter create --org com.xcoder --project-name agentport --platforms=ios .` 生成 `app/ios/`。
- 去掉 `app/android/`，`pubspec.yaml` 的 `dsh_app` 改名 `agentport`，`applicationId` 对应改 bundle id。
- 新仓库 `git init`，首次提交。

### 2. 平台通道处理（35 个）

Dart 代码引用了 35 个平台通道，分三类处理：

- **iOS 需要实现的（约 8 个，写少量 Swift）**：`dsh/app`（前台状态/刷新率/时区）、`dsh/notify` + `actions` + `taps`（远程任务结果推送）、`dsh/links`（深链）、`dsh/share`（分享接收）、`dsh/files`（产物文件）、`dsh/web-files`（WebView 文件选择）、`dsh/diagnostics`（诊断）。
- **iOS 上无意义、直接桩掉**：`dsh/runtime*`、`dsh/phone*`、`dsh/launcher_icon`、`dsh/shortcuts`、`dsh/picture_shortcut`、`dsh/pet_overlay`、`dsh/companion_widget`、`dsh/companion_voice`、`dsh/islands`、`dsh/launch*`、`dsh/dynamic_color`、`dsh/update`、`dsh/usage`——返回安全默认值，Dart 侧拿不到引擎就自然降级。
- **Dart 侧入口隐藏**：本地引擎启动流程、手机操控页、小组件相关设置项在 iOS 上不渲染（按 `Platform.isIOS` 分支），不是隐藏了功能还留着死入口。

### 3. 启动路径

Android 版启动会走本地引擎拉起（PRoot 解压 + 前台服务）。iOS 版启动直接进远程配对/连接流程，复用现有 `lib/remote/`（配对、中继、LAN）与聊天 UI。本地引擎相关的状态初始化在 iOS 分支跳过，避免 MissingPluginException 崩溃。

### 4. 验证

- `flutter analyze`（app）、`flutter test`（Dart 层，桌面引擎可跑 widget/单元测试）。
- Xcode 编译 `app/ios/` 出 `.app`（模拟器目标即可，真机运行未验证）。
- `dart analyze && dart test`（dsh_remote，改动面涉及中继时的契约检查）。

## 留给执行者的判断

- 具体哪些设置页条目在 iOS 隐藏：按"本地引擎 / 手机操控 / 小组件 / 启动视频 / 应用图标 / 统计"六类归并，逐条判断而非机械按通道名屏蔽。
- Swift 原生层的写法：参照 Android 侧对应通道的 Dart 调用约定（入参/返回类型）写，不另起协议。
- l10n：若隐藏入口导致某些文案不再出现，保留 ARB 不动，不重新生成。

## 已定决策（2026-11-13，经 builder check 后确认）

- **后台保活：v1 不做。** 远程任务完成通知依赖服务器侧 APNs（中继服务器目前没有该能力，属服务器项目）或 VoIP 后台模式（苹果审核风险高）。iOS 挂起后本地通知发不出、dart:io WSS 与 WebRTC socket 都会断。v1 采用「前台为主 + 前台自动重连」：锁屏期间不推送，解锁回前台后 `dsh_remote` 的连接层自动 backoff 重连并同步任务状态。后台任务完成推送记为未来事项，等中继服务器支持 APNs 再补。
- **SSH 远程通道：保留。** `dartssh2` 纯 Dart，iOS 可用；不保留反而要改 pubspec、删 `HostKind.ssh` 处理与 SSH 主机表单，保留是省事解。
- **web 模式聊天：保留。** 即把电脑上的 DSH Web（`dsh web` 网页界面）加载进全屏 WebView，iOS 用 `webview_flutter_ios`（WKWebView 是 iOS 一等公民），文件选择走标准 `WKUIDelegate`（几十行 Swift）。体验与安卓版一致。`dsh/web-files` 通道需实现。

## 未决事项

无（bundle id、项目名、远程-only 定位均已确认）。

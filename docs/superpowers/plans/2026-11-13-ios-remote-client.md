# AgentPort iOS 远程客户端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `/Users/joseph/projects/dsh-Go-ios` 建一个独立的 iOS 工程，复用现有 Flutter/Dart 客户端代码，做成只连电脑 DSH 主机的 AgentPort 远程客户端（不做本地引擎、不做手机操控）。

**Architecture:** 复制现有 `app/`（Dart）与纯 Dart 包（`dsh_client`、`dsh_remote`、`dartssh2`），删掉 `app/android/`，`flutter create --platforms=ios` 生成 iOS 壳。Dart 层加 `Platform.isIOS` 分支隐藏本地引擎/手机操控入口；35 个平台通道里 Android 专属的桩掉（返回安全默认值），iOS 需要的约 8 个用少量 Swift 实现。web 模式聊天加 `webview_flutter_ios` 保留。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Riverpod 3、Swift（iOS 原生通道）、Xcode。

**Spec:** `docs/fork/2026-11-13-ios-远程客户端-design.md`（与本计划同在源仓库 dsh-Go，执行前连同本计划拷入新仓库 `docs/`）。

## Global Constraints

- 品牌：iOS bundle id = `com.xcoder.agentport.ios`；应用显示名 = `AgentPort`。Dart 包名保留 `dsh_app`（1025 处引用，重命名无用户收益，见下"我的决定"）。
- 桌面 widget 测试注意：Flutter widget 测试跑在桌面宿主上，`defaultTargetPlatform` 是宿主平台而非 iOS。凡是需要断言 iOS 行为的测试，必须注入可控的平台判定（如把 `isIos` 做成可注入的 provider 或构造函数参数），不能只依赖 `defaultTargetPlatform` 硬比较。
- wire 契约：与 dsh-Go 的客户端一致（plugin 0.6.2 / ds-harness-remote 479b943），协议层不改。
- 远程传输：WebRTC / LAN / TURN / 中继 + **SSH（保留**，纯 Dart `dartssh2`）。
- 后台保活：v1 不做，前台为主 + 前台自动重连（见 spec"已定决策"）。
- web 模式聊天：保留，用 `webview_flutter_ios`，文件选择走 `WKUIDelegate`（`dsh/web-files` 通道需实现）。
- 验证环境：本机 macOS 只有 x86_64 桌面 Flutter 引擎 + Xcode 模拟器目标；真机 iOS 未验证，如实标注。Swift 通道无测试框架，以"Xcode 编译通过 + Dart 侧调用不抛 MissingPluginException"为准。
- 隐藏 ≠ 删代码：本地引擎/手机操控的 Dart 逻辑保留，只在 iOS 上不渲染入口。l10n ARB 不动、不重新生成。

## 我的决定（执行者无需再问，照此办）

- **不重命名 Dart 包名**：`pubspec.yaml` 的 `name: dsh_app` 不动。设备上可见的品牌（应用名、bundle id）已是 AgentPort，包名是内部标识，重命名只是 1025 处 import 的机械改动，不带来任何行为或可见收益。
- **桩通道的默认值**：对"iOS 无意义"的通道，Swift 侧统一返回空/安全默认值（方法调用返回 `null` 或 `false`，事件流为空），让 Dart 侧自然降级，不抛异常。不逐通道写 Swift，用一个通用桩插件注册这些通道名。
- **新仓库不建 `runtime/`、`sdk/`、`tooling/`**：iOS 版用不到引擎补丁、插件 SDK、APK 构建脚本。只拷 `app/`（去 `android/`）+ `packages/`（三个纯 Dart 包）+ `docs/`（设计+计划）。
- **计划文档存放**：本计划与设计文档先放源仓库 `dsh-Go/docs/`，Task 1 建好新仓库后一并拷入 `dsh-Go-ios/docs/`。

## Review Focus

spec 隐含但无任务测试覆盖、最可能咬人的输入/故障模式，按可能性排序。每行已把固定它的测试加进所属任务：

1. **App 切后台再回前台**：远程 socket 被系统掐断，用户重新打开应自动 backoff 重连、恢复到原会话，不崩、不丢正在输入的内容。→ Task 3（Dart 重连/降级单测）。
2. **前台期间远程任务完成**：`dsh/notify` 应触发一条本地通知（iOS 用 `UNUserNotificationCenter`），而不是静默。→ Task 5（Swift 通道，编译验证 + Dart 侧调用不抛异常）。
3. **首次连接某主机**：主机 key 未信任（`HOST_NOT_TRUSTED`）应弹出信任确认，接受后连接、拒绝后给出可恢复的"重新信任"入口，不卡死。→ Task 3（Dart 单测覆盖终态错误码路径）。
4. **web 模式聊天在 iOS 加载电脑端 DSH Web**：WebView 正常渲染，文件选择（`dsh/web-files`）能弹起系统选择器并回传，不白屏、不崩溃。→ Task 6（编译 + Dart 侧 webview 页构建单测）。
5. **iOS 上出现本地引擎/手机操控的死入口**：这些入口在 iOS 上不可用，应完全不渲染（不是点了无反应的按钮）。→ Task 2（widget 测试断言 iOS 分支不渲染）。

---

### Task 1: 项目骨架与 iOS 壳

**Files:**
- Create: `/Users/joseph/projects/dsh-Go-ios/`（新仓库）
- Copy: `dsh-Go/app/`（去 `app/android/`、`app/build/`、`app/.dart_tool/`、`app/.flutter-plugins-dependencies`）、`dsh-Go/packages/{dsh_client,dsh_remote,dartssh2}/`、`dsh-Go/docs/fork/2026-11-13-ios-远程客户端-design.md`、本计划
- Create: `app/ios/`（由 `flutter create` 生成）

**Interfaces:**
- Produces: 可 `flutter pub get` + `flutter analyze` 通过、含 `app/ios/Runner.xcodeproj` 的独立工程；Dart 包名仍为 `dsh_app`，bundle id 待 Task 4 写入 Xcode。

- [ ] **Step 1: 建目录、拷贝**

```bash
mkdir -p /Users/joseph/projects/dsh-Go-ios
cp -R /Users/joseph/projects/dsh-Go/app /Users/joseph/projects/dsh-Go-ios/app
cp -R /Users/joseph/projects/dsh-Go/packages /Users/joseph/projects/dsh-Go-ios/packages
mkdir -p /Users/joseph/projects/dsh-Go-ios/docs/fork
cp /Users/joseph/projects/dsh-Go/docs/fork/2026-11-13-ios-远程客户端-design.md \
   /Users/joseph/projects/dsh-Go-ios/docs/fork/
cp /Users/joseph/projects/dsh-Go/docs/superpowers/plans/2026-11-13-ios-remote-client.md \
   /Users/joseph/projects/dsh-Go-ios/docs/superpowers/plans/ 2>/dev/null || true
rm -rf /Users/joseph/projects/dsh-Go-ios/app/android \
       /Users/joseph/projects/dsh-Go-ios/app/build \
       /Users/joseph/projects/dsh-Go-ios/app/.dart_tool \
       /Users/joseph/projects/dsh-Go-ios/app/.flutter-plugins-dependencies
cd /Users/joseph/projects/dsh-Go-ios && git init
```

- [ ] **Step 2: 生成 iOS 壳（保留现有 Dart，只加平台）**

Run: `cd /Users/joseph/projects/dsh-Go-ios/app && flutter create --org com.xcoder --project-name agentport --platforms=ios .`
Expected: 生成 `app/ios/`，不覆盖 `lib/`、`test/`、`pubspec.yaml`。

- [ ] **Step 3: 拉依赖并静态检查**

Run: `flutter pub get && flutter analyze`
Expected: `No issues found`。若因缺 iOS 平台插件报错，记录错误，留待 Task 4/6 补。

- [ ] **Step 4: 跑 Dart 层测试确认拷贝没改坏**

Run: `flutter test`
Expected: 全绿（与源仓库一致）。若有 Android-only widget 测试因缺原生通道失败，跳过并记录（那是 Task 2/3 的范围）。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "chore(ios): 从 dsh-Go 复制 app 与纯 Dart 包，生成 iOS 壳，删 android/"
```

---

### Task 2: iOS 平台检测 + 隐藏本地引擎/手机操控入口

**Files:**
- Modify: 渲染本地引擎启动、手机操控页、小组件/快捷方式设置的 Dart 文件（`lib/runtime/`、`lib/ui/phone/`、`lib/ui/settings/` 下的入口组件）
- Test: `test/ios_feature_visibility_test.dart`

**Interfaces:**
- Produces: 平台判定 `isIosProvider`（`Provider<bool>`，默认值 `defaultTargetPlatform == TargetPlatform.iOS`，测试可 override）与便捷 getter `isIos`（从 `isIosProvider` 读），放 `lib/state/platform_state.dart`（新增）。各入口组件读 provider 决定是否渲染，测试通过 override provider 注入平台。

- [ ] **Step 1: 写失败的 widget 测试**

```dart
testWidgets('iOS 不渲染本地引擎启动入口', (tester) async {
  // override isIosProvider 为 true（模拟 iOS 宿主），泵入主 shell/设置页，
  // 断言本地引擎启动按钮与手机操控入口 widget 不存在
  // expect(find.byType(LocalEngineLaunchButton), findsNothing);
  // expect(find.byType(PhoneControlPage), findsNothing);
});
testWidgets('Android 仍渲染本地引擎启动入口', (tester) async {
  // override isIosProvider 为 false，断言入口存在（防止把功能锁死）
  // expect(find.byType(LocalEngineLaunchButton), findsOneWidget);
});
```

（具体 widget 类型名按实际入口组件确定；测试要能证明"iOS 上这些入口不渲染、Android 上仍渲染"。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ios_feature_visibility_test.dart`
Expected: FAIL（入口目前无条件渲染）。

- [ ] **Step 3: 实现 `lib/state/platform_state.dart` 并在各入口加 iOS 分支**

新增 `platform_state.dart` 暴露 `isIos`。在每个本地引擎/手机操控/小组件/快捷方式入口组件里，iOS 时返回空/不渲染（`if (isIos) return const SizedBox.shrink();` 或直接从导航树剔除）。只改渲染层，不删 Dart 逻辑。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ios_feature_visibility_test.dart`
Expected: PASS。

- [ ] **Step 5: 全量 analyze + test，提交**

Run: `flutter analyze && flutter test`
```bash
git add -A && git commit -m "feat(ios): 平台检测，iOS 隐藏本地引擎/手机操控/小组件入口"
```

---

### Task 3: 桩掉 Android 专属通道 + 远程客户端启动路径

**Files:**
- Modify: 启动路径 `lib/main.dart`、`lib/launch/launch_state.dart`（iOS 跳过本地引擎拉起）；Dart 侧各通道封装确认缺通道时不抛（多数已有 try/catch）
- Test: `test/ios_boot_degrade_test.dart`、`test/remote_reconnect_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `isIos`。
- Produces: iOS 上启动不进本地引擎流程，直接进远程配对/连接；远程断线后回前台自动重连。Review Focus #1、#3 的测试在此。

- [ ] **Step 1: 写启动降级失败测试**

```dart
testWidgets('iOS 冷启动不调用本地引擎通道', (tester) async {
  // 记录 dsh/runtime 的 invokeMethod 调用，iOS 启动后断言 start/install 未被调用
});
```

- [ ] **Step 2: 写远程重连失败测试**

```dart
test('前台期间远程连接断开后自动 backoff 重连并恢复会话', () async {
  // 用 dsh_remote 的连接状态机，模拟 connected -> dropped，
  // 断言进入 retrying 且再次 connected 后会话状态恢复
});
test('首次连接未信任主机弹信任确认，拒绝后可恢复重信任', () async {
  // 模拟 HOST_NOT_TRUSTED 终态，断言有"重新信任"恢复路径而非永久卡死
});
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/ios_boot_degrade_test.dart test/remote_reconnect_test.dart`
Expected: FAIL。

- [ ] **Step 4: 实现**

- 启动路径：`main()`/`LaunchController` 在 `isIos` 时跳过 `RuntimeBridge.start/install` 与 `dsh/launch` 冷启动，直接进远程连接 UI。
- 确认 Dart 通道封装对 `MissingPluginException` 已有 try/catch 降级（没有的补上，保持"拿不到引擎自然降级"的语义）。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/ios_boot_degrade_test.dart test/remote_reconnect_test.dart && flutter analyze`
Expected: PASS + 无告警。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat(ios): 启动跳过本地引擎，远程断线自动重连，通道缺省不抛"
```

---

### Task 4: Swift 原生通道（实现 + 通用桩）

**Files:**
- Create: `app/ios/Runner/iOSChannels/` 下若干 Swift 文件：一个通用桩插件（注册所有"iOS 无意义"通道名，统一返回安全默认值/空事件流）+ 若干实现插件（`dsh/app`、`dsh/notify`+`taps`+`actions`、`dsh/links`、`dsh/share`、`dsh/files`、`dsh/web-files`、`dsh/diagnostics`）
- Modify: `app/ios/Runner/AppDelegate.swift`（注册所有插件）、`app/ios/Runner/Info.plist`（bundle id `com.xcoder.agentport.ios`、应用名 `AgentPort`、通知权限）

**Interfaces:**
- Consumes: Dart 侧各通道的方法名与入参/返回类型（执行者读对应 Dart 调用点确定，不另起协议）。
- Produces: iOS 上这些通道可被 Dart 调用而不抛 `MissingPluginException`。Review Focus #2、#4 的编译验证在此。

- [ ] **Step 1: 通用桩插件**

写一个 Swift 插件，注册所有 Android 专属通道（`dsh/runtime`、`dsh/runtime/events`、`dsh/phone*`、`dsh/launcher_icon`、`dsh/shortcuts`、`dsh/picture_shortcut`、`dsh/pet_overlay`、`dsh/companion_*`、`dsh/islands`、`dsh/launch*`、`dsh/dynamic_color`、`dsh/update`、`dsh/usage`、`dsh/media*`、`dsh/native-*`、`dsh/performance*`、`dsh/voice*` 等），方法调用统一返回 `null`/`false`，事件流为空。让 Dart 侧自然降级。

- [ ] **Step 2: 实现 8 个 iOS 需要的通道**

按 Dart 调用约定实现：`dsh/app`（前台 bringToFront、刷新率、时区）、`dsh/notify` 家族（`UNUserNotificationCenter` 本地通知 + tap 事件流）、`dsh/links`（深链）、`dsh/share`（分享接收）、`dsh/files`（产物文件读写）、`dsh/web-files`（`WKUIDelegate` 文件选择）、`dsh/diagnostics`（诊断信息）。

- [ ] **Step 3: 注册进 AppDelegate + 写 Info.plist**

所有插件在 `application(_:didFinishLaunchingWithOptions:)` 注册。Info.plist 设 bundle id、CFBundleDisplayName=AgentPort、`NSUserNotificationsUsageDescription`。

- [ ] **Step 4: 编译验证（无真机，模拟器目标）**

Run: `cd /Users/joseph/projects/dsh-Go-ios/app && flutter build ios --simulator`
Expected: 编译通过（Xcode 无错）。真机运行未验证，如实记录。

- [ ] **Step 5: Dart 侧调用不抛异常（回归）**

Run: `flutter test`（含 Task 3 的启动降级测试，确认通道已注册后不再 MissingPlugin）
```bash
git add -A && git commit -m "feat(ios): Swift 原生通道（实现 8 个 + 通用桩），Info.plist 品牌"
```

---

### Task 5: 通知权限 + 任务完成通知闭环

**Files:**
- Modify: `app/ios/Runner/iOSChannels/` 的通知插件（Task 4 的 `dsh/notify`）
- Test: `test/ios_notify_contract_test.dart`（Dart 侧契约：调用 notify 通道不抛、返回成功）

**Interfaces:**
- Consumes: Task 4 的 `dsh/notify` 通道。
- Produces: 前台远程任务完成时发一条本地通知。Review Focus #2 在此。

- [ ] **Step 1: 写 Dart 侧通知契约测试**

```dart
test('iOS 上调用 dsh/notify 通知通道不抛异常且返回成功', () async {
  // 在已注册通道的宿主下调用发送方法，断言返回成功、无 MissingPluginException
});
```

- [ ] **Step 2: 跑测试确认失败/通过基线**

Run: `flutter test test/ios_notify_contract_test.dart`
Expected: 若 Task 4 已注册通道则 PASS（这是契约回归，非新功能失败）；若尚未注册则 FAIL，先确认 Task 4 完成。

- [ ] **Step 3: 确认 Swift 侧请求通知权限并在任务完成时调度本地通知**

`UNUserNotificationCenter` 请求授权、任务完成回调时 `add` 一条通知。编译验证。

Run: `flutter build ios --simulator`
Expected: 编译通过。

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "feat(ios): 通知权限与远程任务完成本地通知"
```

---

### Task 6: web 模式聊天（webview_flutter_ios + 文件选择）

**Files:**
- Modify: `app/pubspec.yaml`（加 `webview_flutter` 与 `webview_flutter_ios`，去掉仅 Android 的 `webview_flutter_android` 依赖或保留双端）、`lib/ui/web/` 相关文件确认 iOS 分支
- Test: `test/ios_webview_chat_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `dsh/web-files` 通道（文件选择）。
- Produces: iOS 上 web 模式聊天页可构建、WebView 加载电脑端 DSH Web。Review Focus #4 在此。

- [ ] **Step 1: 写 webview 页构建测试**

```dart
testWidgets('iOS 上 web 模式聊天页可构建并加载 DSH Web URL', (tester) async {
  // 泵入 web 模式页，断言 WebView ���台视图被构建、加载的目标 URL 正确
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ios_webview_chat_test.dart`
Expected: FAIL（缺 `webview_flutter_ios`）。

- [ ] **Step 3: 加依赖并接 iOS 实现**

`pubspec.yaml` 加 `webview_flutter`、`webview_flutter_ios`。确认 `lib/ui/web/web_view_page.dart` 在 iOS 上走 WKWebView，文件选择走 Task 4 的 `dsh/web-files`。

- [ ] **Step 4: 跑测试确认通过 + 编译**

Run: `flutter test test/ios_webview_chat_test.dart && flutter build ios --simulator`
Expected: PASS + 编译通过。

- [ ] **Step 5: 全量回归 + 提交**

Run: `flutter analyze && flutter test && flutter build ios --simulator`
```bash
git add -A && git commit -m "feat(ios): web 模式聊天（webview_flutter_ios）与文件选择"
```

---

## 收尾验证（非独立任务，执行完跑一遍）

- `flutter analyze && flutter test`（app）全绿。
- `flutter build ios --simulator` 编译通过。
- 如实记录：真机 iOS 未运行、Swift 通道无测试框架仅编译验证、后台保活 v1 未做。
- 报告最终提交与未决事项。

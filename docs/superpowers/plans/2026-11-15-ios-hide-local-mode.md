# iOS 本地模式完整隐藏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 上任何路径（菜单、空状态、搜索、外链、插件跳转、抽屉、网页模式）都不出现本地引擎/手机操控入口；当前主机为 local 时统一呈现"未选择主机 → 远程连接引导"；被禁页面经直接路由打开被拦截。Android 行为零变化。

**Architecture:** 三层拦截：能力 provider（`localEngineSupportedProvider`/`phoneControlSupportedProvider`）→ 访问层单点（`settingsPage()` switch 表 + 目录 item 查询，被禁 id 返回占位页；链接解析返回 null 走 LinkRouter 既有 toast）→ 展示层逐入口隐藏（评估 §3 十二项清单）。统一"未选择主机"状态由 `ActiveHostController.ready` 后判定，五种 local 来源呈现同一引导。

**Tech Stack:** Flutter/Dart、Riverpod 3、widget 测试（桌面宿主，override provider 注入平台）。

**Spec:** `docs/fork/2026-11-15-ios-本地模式隐藏-design.md`（含 builder check 四条裁决；输入评估 `docs/fork/2026-11-15-ios-本地模式隐藏可行性评估.md`）

## Global Constraints

- 不删代码、不改 `HostKind`/`HostRef.local`/序列化编码、不迁移旧偏好；wire 契约不动。
- 门禁基建：沿用 `isIosProvider`（`lib/state/platform_state.dart`，可 override）；widget 测试一律 override provider 注入平台，不依赖宿主 `defaultTargetPlatform`。
- 验收范围（裁决 Q1）：iOS 不发起本地引擎**安装/启动/连接**尝试；冷启动一次 `dsh/runtime` `status()` 桩轮询可接受，不门禁。
- 门禁落点（裁决 Q2）：`settingsPage(SettingsPageId)` switch 表 + 功能目录 item 查询两处真单点；链接路径解析为 null 复用 `app_links.dart:308` 既有"无法打开链接"兜底，不新增文案。
- 手机操控与本地引擎是**两个独立能力** provider，不合并。
- 新文案：`app/lib/l10n/parts/*.arb` 中英同步，跑 `python3 app/tool/l10n_merge.py`；不手改生成物。
- 验证：`flutter analyze` + `flutter test`（`DSH_TEST_FONT_DIR=/private/tmp/claude-501/dsh-test-fonts`）+ `flutter build ios --simulator`；flutter 命令需沙箱外执行。golden 失败与 access_flow 失败为既有环境性基线，不算回归。
- 分支：`dev/ios-hide-local`（已建，含设计文档提交 `8470b8e`）。

## Review Focus

1. **五种 local 来源呈现同一引导**（全新安装/旧 local 偏好/删除当前主机/退出远程账号/关自动连接重启）：都进"未选择主机"远程引导，不出现本地安装入口，`ready` 前不闪配对页。→ Task 3（`ios_unselected_host_state_test.dart` 逐来源断言；`forget()` 回落路径含在内）。
2. **被禁页面不能从任何路径打开**：外链 `dshgo://open/*`、插件 `native_taps`、搜索历史/结果、`HomeShell._openDestination`、直接构造 `LocalInstallPage`。→ Task 1（路由测试）+ Task 4（搜索/目录）+ Task 5（直接构造点）。
3. **远程共用能力不误伤**：引擎参数、模型、权限、插件、诊断、主机管理在 iOS 照常打开。→ Task 1 反向对照断言（`engineParams`/`models`/`remote` 未被拦）。
4. **Android 零回归**：本机行、安装入口、自动启动、手机操控页照常。→ Task 2/3 的 Android 对照用例 + 既有 `root_gate_autostart_test` 等全绿（Task 7）。
5. **连接失败 ≠ 未选择主机**：远程主机连接失败时仍显示该主机与重试/切换，不进未选择引导。→ Task 3（failed link 状态用例）。

---

### Task 1: 能力 provider + 访问层单点门禁

**Files:**
- Modify: `app/lib/state/platform_state.dart`（新增两个能力 provider）
- Modify: `app/lib/ui/settings/index/settings_pages.dart`（`settingsPage()` 门禁 + 被禁 id 集合）
- Create: `app/lib/ui/settings/blocked_page.dart`（占位页 widget）
- Modify: `app/lib/links/page_links.dart`（`pageForId` 被禁 id → null）
- Test: `app/test/ios_blocked_page_routing_test.dart`

**Interfaces:**
- Produces:
  - `localEngineSupportedProvider = Provider<bool>((ref) => !ref.watch(isIosProvider))`
  - `phoneControlSupportedProvider = Provider<bool>((ref) => !ref.watch(isIosProvider))`（独立声明，值暂同引擎）
  - `const localEngineOnlyPageIds = {SettingsPageId.engine, SettingsPageId.background, SettingsPageId.systemAccess}`
  - `const phoneControlPageIds = {SettingsPageId.phone, SettingsPageId.phoneAppRules, SettingsPageId.phoneAndroidShell, SettingsPageId.phoneDnd, SettingsPageId.phoneUnlocks}`
  - `bool settingsPageBlocked(SettingsPageId id, {required bool engineBlocked, required bool phoneBlocked})`（纯函数；**能力以两个 bool 参数传入，不读 provider**——`settingsPage()` 是无 ref 纯函数，全链统一传能力结果，页面/搜索/操作层共用同一判定，不各算一套）
  - `settingsPage` 签名改为 `Widget settingsPage(SettingsPageId id, {String? sessionId, required bool engineBlocked, required bool phoneBlocked})`；所有调用点（`settingsPageForLink`、`spotPage`、搜索、`HomeShell._openDestination`）从各自最近的 ref 上下文传入两能力值。`settingsPageForLink`/`pageForId` 参数从 `isIos` 改为同样的两个 bool。
  - `class BlockedFeaturePage extends StatelessWidget`（构造参数 `{super.key}`；文案 l10n key `iosFeatureUnavailable`，Task 2 加 ARB，本任务先用 `Text('iosFeatureUnavailable')` 占位并在测试中按 key 名断言）
- Consumes: Task 无前置；后续任务读以上全部。

- [ ] **Step 0: 记录基线失败清单（开工前，供 Task 7 逐项对比）**

```bash
ws=.superpowers/sdd/2026-11-15-ios-hide-local-mode
mkdir -p "$ws"
cd app && DSH_TEST_FONT_DIR=/private/tmp/claude-501/dsh-test-fonts flutter test > "$ws/baseline_suite.log" 2>&1; echo "exit: $?"
grep "Failing tests:" -A 9999 "$ws/baseline_suite.log" | grep "^  /" > "$ws/baseline_failures.txt"
wc -l "$ws/baseline_failures.txt"   # 记录条数（预期 ≈1202，golden+access_flow）
```

- [ ] **Step 1: 写失败的路由测试**

```dart
// ios_blocked_page_routing_test.dart
test('iOS 被禁 id 集合完整且不误伤共用页', () {
  for (final id in [...localEngineOnlyPageIds, ...phoneControlPageIds]) {
    expect(settingsPageBlocked(id, engineBlocked: true, phoneBlocked: true), isTrue);
  }
  for (final id in [SettingsPageId.engineParams, SettingsPageId.models, SettingsPageId.remote,
      SettingsPageId.plugins, SettingsPageId.diagnostics, SettingsPageId.permission]) {
    expect(settingsPageBlocked(id, engineBlocked: true, phoneBlocked: true), isFalse); // Review Focus #3
  }
});
test('Android 能力不拦任何页', () {
  expect(settingsPageBlocked(SettingsPageId.engine, engineBlocked: false, phoneBlocked: false), isFalse);
});
testWidgets('iOS settingsPage(engine) 返回 BlockedFeaturePage', (tester) async { /* pump + find.byType(BlockedFeaturePage) */ });
testWidgets('iOS pageForId 对被禁 id 返回 null（走 LinkRouter toast）', (tester) async { /* 断言 pageForId('engine', null) == null */ });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ios_blocked_page_routing_test.dart`
Expected: FAIL（符号不存在）。

- [ ] **Step 3: 实现**

`platform_state.dart` 加两个 provider；`settings_pages.dart` 顶部加两个 const 集合 + `settingsPageBlocked` 纯函数，`settingsPage()` switch 前加：被拦时 `return BlockedFeaturePage()`；`page_links.dart` 的 `pageForId` 在 `settingsPageForLink` 命中后查 `settingsPageBlocked`（`isIos` 由调用方传入：给 `pageForId`/`settingsPageForLink` 增加 `{required bool isIos}` 参数，LinkRouter 调用点传 `ref.watch(isIosProvider)`）。`blocked_page.dart` 新建占位页。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ios_blocked_page_routing_test.dart`
Expected: PASS。

- [ ] **Step 5: analyze + 提交**

```bash
flutter analyze  # 零 error/warning
git add app/lib/state/platform_state.dart app/lib/ui/settings/index/settings_pages.dart app/lib/ui/settings/blocked_page.dart app/lib/links/page_links.dart app/test/ios_blocked_page_routing_test.dart <pageForId/settingsPageForLink 的调用方文件>
git commit -m "feat(ios): 能力 provider + settingsPage 单点门禁（被禁页占位/链接解析 null）"
```

---

### Task 2: 主机切换器 + "未选择主机"展示 + 返回本机 + 设置页剩余直接入口

**Files:**
- Modify: `app/lib/ui/remote/host_switcher.dart:100-135`（本机行不渲染；标识展示）、`:35` 附近
- Modify: `app/lib/ui/remote/remote_screen.dart:189,215`（"返回本机"门禁）
- Modify: `app/lib/state/hosts_state.dart` 或 `hostNameProvider` 所在文件（iOS+local → "未选择主机"）
- Modify: `app/lib/ui/settings/settings_screen.dart:242-256`（**背景保活、系统权限两瓦片直接构造 `BackgroundGuidePage`/`SystemAccessPage`，不经 `settingsPage()`——随 `localEngineSupportedProvider` 隐藏**，评审补漏）
- Modify: `app/lib/l10n/parts/*.arb`（`hostUnselected`、`iosFeatureUnavailable` 中英）+ 跑 `l10n_merge.py`
- Modify: `app/lib/ui/settings/settings_screen.dart`（既有三处 `isIosProvider` 改读能力 provider——引擎瓦片/footer 读 `localEngineSupportedProvider`，手机操控瓦片读 `phoneControlSupportedProvider`）
- Test: `app/test/ios_feature_visibility_test.dart`（扩展）

**Interfaces:**
- Consumes: Task 1 的两个能力 provider。
- Produces: l10n key `hostUnselected`（"未选择主机"/"No host selected"）、`iosFeatureUnavailable`（"此功能在 iOS 上不可用"/"Not available on iOS"）；`BlockedFeaturePage` 改用 `iosFeatureUnavailable` 真文案。

- [ ] **Step 1: 扩展可见性测试（失败）**

```dart
testWidgets('iOS 主机切换器无本机行，标识为未选择主机', (tester) async {
  // override isIosProvider=true + activeHost=local + hosts 空
  // 打开 host_switcher：expect(find.text('本机'), findsNothing);
  // expect(find.text('未选择主机'), findsOneWidget);
});
testWidgets('Android 主机切换器本机行照常', (tester) async { /* findsOneWidget */ });
testWidgets('iOS 设置页无背景保活/系统权限瓦片（直接构造入口补漏）', (tester) async {
  // 泵 SettingsScreen（同文件既有 _overrides 手法），滚动到通用组
  // expect(find.textContaining('后台运行'), findsNothing);   // 实际文案以 l10n key 为准
  // expect(find.textContaining('系统权限'), findsNothing);
  // Android 对照：findsOneWidget ×2
});
```

- [ ] **Step 2: 跑测试确认失败** — Run: `flutter test test/ios_feature_visibility_test.dart` Expected: FAIL。

- [ ] **Step 3: 实现**

ARB 加两 key（中英）→ `python3 app/tool/l10n_merge.py`；`host_switcher` 本机行 `if (ref.watch(localEngineSupportedProvider))` 包裹，无远程主机时列表尾部给"添加/登录远程主机"入口（复用既有 `RemoteScreen` 行样式）；`remote_screen.dart:215` 返回本机按钮同门禁；主机名展示：iOS 且 `host.isLocal` 且未 ready 后选择过 → `l10n.hostUnselected`（判定函数放 `hosts_state.dart`：`String hostDisplayName(HostRef host, {required bool isIos})` 或 provider，执行者按现有 `hostNameProvider` 形态并入）。`settings_screen.dart` 三处改读能力 provider，**背景保活/系统权限两瓦片（`:242-256`）随 `localEngineSupportedProvider` 隐藏**。`BlockedFeaturePage` 换真文案。

- [ ] **Step 4: 跑测试确认通过** — 同 Step 2 命令，Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat(ios): 主机切换器隐本机行，local 显示'未选择主机'，返回本机门禁；能力 provider 替换既有直读"
```

---

### Task 3: 空状态引导 + ready 帧 + 网页模式

**Files:**
- Modify: `app/lib/ui/chat/chat_screen.dart:1481-1495`（`localIdle` 分支 iOS → 远程引导）
- Modify: `app/lib/ui/shell/sessions_drawer.dart:826`（`_EmptyState` local 分支）、`:951`（状态区本机名）
- Modify: `app/lib/ui/shell/root_gate.dart:352`（`waitsForEngine: ref.read(activeHostProvider).isLocal` → `!isIos && isLocal`）
- Modify: `app/lib/ui/web/local_web_screen.dart:76`（iOS 禁入本地网页流程）与 `lib/ui/web/mode_home.dart`/`web_home.dart`（未选主机的网页首页退化）
- Test: `app/test/ios_unselected_host_state_test.dart`

**Interfaces:**
- Consumes: Task 1 能力 provider、Task 2 `hostUnselected` 文案。
- Produces: `activeHostReadyProvider = Provider<Future<bool>>`（body：`ref.read(activeHostProvider.notifier).ready.then((_) => true)`，放 `hosts_state.dart`）；RootGate 以它 gate `_Splash`。无其他新接口；行为=Review Focus #1、#5。

- [ ] **Step 1: 写失败测试（五种来源走真实流程，不是 override 终态）**

```dart
// 共同断言 helper：iOS 引导出现、无安装入口、hostUnselected 标识
// (a) 全新安装：SharedPreferences 无 prefsKey，泵 ActiveHostController（真实 _restore），ready 完成后 → 引导
// (b) 旧 local 偏好：prefs 预置 HostRef.local.encode() → 引导
// (c) 删除当前主机：activeHost=ssh(lab)，调 ActiveHostController.forget((h)=>true)（真实删除路径）→ 回落 local → 引导出现
// (d) 退出远程账号：走 relay 账号登出触发的 forget 链（若与 (c) 同汇聚点则复用，注明证据）
// (e) 关自动连接重启：autoConnect=false + prefs 存 ssh(lab)，泵 controller → 保持 local → 引导，且不擅自连接（connector 调用数 0）
testWidgets('iOS local 主机：聊天空状态显示远程引导，无安装按钮', ...);
testWidgets('iOS local 主机：抽屉空状态同为引导', ...);
testWidgets('ready 前不闪引导：ready 挂起时保持启动画面', (tester) async {
  // override ActiveHostController.ready 为永不完成 → 泵出 _Splash，不出现配对页
});
testWidgets('ready 后恢复到远程主机：直接进远程流程，不出引导', (tester) async {
  // prefs 存 ssh(lab) + autoConnect=true → ready 完成后 activeHost==ssh(lab)，无 hostUnselected
});
testWidgets('远程连接失败仍显示该主机与重试，不进未选择引导', ...);
  // activeHost=ssh(lab) + link=failed → expect 主机名存在、hostUnselected 不存在
testWidgets('Android local 主机安装入口照常', ...);
```

- [ ] **Step 2: 跑测试确认失败** — Run: `flutter test test/ios_unselected_host_state_test.dart` Expected: FAIL。

- [ ] **Step 3: 实现（含 ready 等待机制，评审补漏）**

**谁等待**：`root_gate.dart` 的 build 首帧判定加 `final hostReady = ref.watch(activeHostReadyProvider)`（新增：`Provider<Future<bool>>`，body = `activeHostProvider.notifier.ready.then((_) => true)`；Riverpod 里 watch future provider 未完成时 `value == null`）。**等待期间**：`child` 保持 `_Splash`（与 settings/runtime/prefs loaded 同层条件），**完成后**：state 已 settle，按 `isIos && activeHost.isLocal` 出引导，否则正常 home。**`waitsForEngine`**：`:356` 改 `!isIos && ref.read(activeHostProvider).isLocal`——注意这只管启动画面退场时机，**不等 ready 的缺口由上面的 activeHostReadyProvider 补**，两者都要。`chat_screen` 的 `idle` switch：`localEngineSupported` 为 false 时 `localIdle` 置 null，改走既有 `_RemoteEmptyState`/引导分支（缺则按 drawer 同款小引导）；`sessions_drawer._EmptyState` 首行 `if (!host.isLocal)` 之前加 iOS+local → 引导；`:951` 名字走 Task 2 展示函数；`local_web_screen` 入口（`HomeShell._openDestination` 的 web 目的地 + 页面内安装/启动按钮）加 `localEngineSupported` 门禁——被拦时显示引导而非报错页。

- [ ] **Step 4: 跑测试确认通过** — 同 Step 2，Expected: PASS。

- [ ] **Step 5: 全量 web/chat/drawer 相关测试回归 + 提交**

```bash
flutter test test/shell test/chat test/web test/remote 2>&1 | tail -3   # 无新增失败
git add -A && git commit -m "feat(ios): 聊天/抽屉空状态与网页模式统一'未选择主机'远程引导，ready 前不闪，失败≠未选"
```

---

### Task 4: 搜索与功能目录过滤

**Files:**
- Modify: `app/lib/ui/settings/search/settings_search_page.dart:128-138,163`（索引过滤）
- Modify: `app/lib/ui/settings/index/spots.dart`（或搜索索引构建处：以实际过滤最小点为准）
- Modify: `app/lib/ui/features/feature_catalog.dart`（手机操控/引擎类条目按能力过滤）
- Test: `app/test/ios_blocked_page_routing_test.dart`（扩展）

**Interfaces:**
- Consumes: Task 1 的 `settingsPageBlocked` + 两个 id 集合。
- Produces: `Iterable<SettingSpot> visibleSettingSpots(Iterable<SettingSpot> all, {required bool engineBlocked, required bool phoneBlocked})`（入口行按 `spot.opens`、普通行按 `spot.page` 判定，供搜索与目录共用；若执行者发现更小的共用点，用它替代并同步测试）。

- [ ] **Step 1: 写失败测试**

```dart
test('搜索索引 iOS 剔除本地页及其入口（按目标页判断）', () {
  // 判定函数：spotBlocked(spot) = settingsPageBlocked(spot.isEntry ? spot.opens! : spot.page, ...)
  // 入口行按 opens（目标页）判，普通行按 page（所在页）判——评审补漏：
  // 本机引擎入口行的 page 是 hub、opens 是 engine，只按 page 判会漏。
  final visible = visibleSettingSpots(SettingsIndex.spots, engineBlocked: true, phoneBlocked: true);
  expect(visible.any((s) => s.opens == SettingsPageId.engine || s.page == SettingsPageId.engine), isFalse);
  expect(visible.any((s) => s.opens == SettingsPageId.phone || s.page == SettingsPageId.phone), isFalse);
  expect(visible.any((s) => s.opens == SettingsPageId.engineParams || s.page == SettingsPageId.engineParams), isTrue); // 共用保留
});
testWidgets('iOS 搜索"引擎"不出本机引擎结果；历史命中被拦', ...);
```

- [ ] **Step 2: 跑测试确认失败** — Expected: FAIL。

- [ ] **Step 3: 实现**

`visibleSettingSpots(Iterable<SettingSpot>, {required bool engineBlocked, required bool phoneBlocked})`：`spot.isEntry ? spot.opens : spot.page` 命中被禁集合则剔除（入口与子行一并）；搜索索引与全部功能列表共用它，`feature_catalog` 的手机操控/引擎条目加 `needsLocalEngine`/`needsPhoneControl` 标记并按能力过滤（标记方式按目录现有字段形态，不新建框架）。

- [ ] **Step 4: 跑测试确认通过** — Expected: PASS。

- [ ] **Step 5: 提交** — `git commit -m "feat(ios): 搜索索引与功能目录过滤本地专属页"`

---

### Task 5: 隐私页/诊断页跳转 + 安装操作兜底

**Files:**
- Modify: `app/lib/ui/settings/privacy_page.dart:37`（OCR 说明区块及其跳转）
- Modify: `app/lib/ui/settings/diagnostics_page.dart:242`（跳手机操控的入口）
- Modify: `app/lib/ui/shell/system_entry_host.dart` 或 `openLocalInstall` helper 所在文件（操作层兜底）
- Test: `app/test/ios_blocked_page_routing_test.dart`（扩展）

**Interfaces:**
- Consumes: Task 1 能力 provider。
- Produces: 无新接口。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('iOS 隐私页无 OCR 区块跳转；诊断页无手机操控跳转', (tester) async {
  // 泵两页，expect(find.text(手机操控相关文案), findsNothing)
});
test('iOS openLocalInstall 明确失败不静默', () async {
  // 调用后断言返回/抛出的错误码存在（不可用提示），未 await 悬挂
});
```

- [ ] **Step 2: 跑测试确认失败** — Expected: FAIL。

- [ ] **Step 3: 实现**

`phoneControlSupportedProvider` 为 false 时隐私页 OCR 区块整块不渲染、诊断页手机操控跳转行不渲染（保留通用诊断其余部分）；`openLocalInstall`（及 `host_switcher` 直接构造 `LocalInstallPage` 的调用点——Task 2 已随本机行隐藏，此处确认无其他构造者）iOS 时返回明确失败（沿用 `PlatformException` 风格错误码 `local_unsupported`）。

- [ ] **Step 3b: 排查插件跳转旁路 `native_taps.dart`**

读 `app/lib/ui/plugins/native/native_taps.dart` 对 `settingsPageForLink` 的调用：Task 1 已给该函数加 `isIos` 参数，确认 native_taps 调用点传了 `ref.watch(isIosProvider)`（或被同一门禁覆盖）；若它绕过了 `settingsPageForLink` 自行构造页面，补同款门禁并加一条断言进本任务测试（`testWidgets('iOS 插件 tap 被禁页走拦截', ...)`）。在提交信息里写明排查结论。

- [ ] **Step 4: 跑测试确认通过** — Expected: PASS。

- [ ] **Step 5: 提交** — `git commit -m "feat(ios): 隐私/诊断本地跳转隐藏，安装操作层兜底"`

---

### Task 6: 状态层本地连接短路

**Files:**
- Modify: `app/lib/state/connection_state.dart`（local 主机连接建立汇聚点）
- 视调用链证据可能触及：`lib/state/bots_state.dart`、`lib/state/notify_state.dart`、`lib/pets/pet_signals.dart` 等（仅当汇聚点覆盖不到时逐处加）
- Test: `app/test/ios_state_layer_no_local_calls_test.dart`

**Interfaces:**
- Consumes: Task 1 `localEngineSupportedProvider`。
- Produces: 无新接口；行为=设计"状态层补充"。

- [ ] **Step 1: 写失败测试（构造"本会连接"的场景，证明门禁有效——评审补漏：桩环境空连接会假通过）**

```dart
// 关键：localRuntimeProvider 给 running + 有效 baseUrl/token（不是 notInstalled），
// 现状下 LocalConnectionController 会真的发起连接。
test('iOS：running 本机 + 有效地址时 localClientConnectorProvider 调用数为 0', () async {
  var connectorCalls = 0;
  // override localClientConnectorProvider 为计数 connector（返回假 DshClient/抛断言）
  // override localRuntimeProvider → RuntimeStatus(phase: running, baseUrl 有效…), isIos=true, activeHost=local
  // 直接订阅 localConnectionProvider（await future），断言 connectorCalls == 0 且值为 null
});
test('Android 对照：同场景 connector 被调用 ≥1 次', () async { /* isIos=false → connectorCalls >= 1 */ });
```

- [ ] **Step 2: 跑测试确认失败** — Run: `flutter test test/ios_state_layer_no_local_calls_test.dart` Expected: iOS 用例 FAIL（现状会调用 connector）。此测试以 running+有效地址构造，不存在"桩下自然为空"的假通过；若意外 PASS，读 `LocalConnectionController` 源码找真实触发条件并加强场景，直到 RED 成立。

- [ ] **Step 3: 实现**

在 `connection_state.dart` 对 local 主机的连接建立处加 `localEngineSupported` 短路（返回 null 连接，与"主机离线"同形，走既有降级 UI）；其余 state 文件不改——以 Step 1 测试与调用链 grep 证明汇聚点覆盖；覆盖不到的再逐处加并在提交信息列明。

- [ ] **Step 4: 跑测试确认通过 + Android 对照**

Run: `flutter test test/ios_state_layer_no_local_calls_test.dart test/state 2>&1 | tail -3`
Expected: 新测试 PASS；`test/state` 无新增失败。

- [ ] **Step 5: 提交** — `git commit -m "feat(ios): local 主机连接在汇聚点短路，state 层不再触达本地引擎"`

---

### Task 7: 全量回归 + 构建 + 文档

**Files:**
- Modify: `docs/fork/2026-11-15-ios-本地模式隐藏-design.md`（追加"实施结果"节）

- [ ] **Step 1: 全量验证（完整日志落盘，退出码不经过管道）**

```bash
ws=.superpowers/sdd/2026-11-15-ios-hide-local-mode
flutter analyze > "$ws/analyze.log" 2>&1; echo "analyze exit: $?"     # 期望 0（零 error/warning）
flutter test > "$ws/final_suite.log" 2>&1; echo "test exit: $?"        # 失败清单逐项对比 baseline
grep -A 9999 "Failing tests:" "$ws/final_suite.log" | grep "^  /" > "$ws/final_failures.txt"
diff "$ws/baseline_failures.txt" "$ws/final_failures.txt"               # 期望：无新增用例名
flutter test test/ios_feature_visibility_test.dart test/ios_boot_degrade_test.dart \
  test/ios_notify_contract_test.dart test/ios_blocked_page_routing_test.dart \
  test/ios_unselected_host_state_test.dart test/ios_state_layer_no_local_calls_test.dart \
  > "$ws/ios_tests.log" 2>&1; echo "ios tests exit: $?"                 # 期望 0
flutter build ios --simulator > "$ws/build.log" 2>&1; echo "build exit: $?"   # 期望 0，✓ Built
python3 app/tool/l10n_merge.py --check                                   # 通过
```

- [ ] **Step 2: 设计文档追加实施结果**（做了什么、验收逐条、真机未验证声明）

- [ ] **Step 3: 提交** — `git commit -m "docs(fork): 本地模式隐藏实施结果 + 全量回归记录"`

---

## 收尾验证（非独立任务）

- 全部 6 个新/扩展测试文件在 iOS 注入下绿、Android 对照用例绿。
- **逐项失败对比（评审补漏：不比数量）**：开工前记录基线失败清单——`flutter test` 全量输出中 `Failing tests:` 段的**用例名逐行**存 `workspace/baseline_failures.txt`（预期：golden 字体渲染类 + `access_flow_test` 1 个）；收尾再存 `final_failures.txt`，`diff` 两者——**任何新增用例名即回归，任何消失也要查明原因**（可能是被改坏的测试没跑到）。命令保留退出码：`flutter test > log 2>&1; echo "exit: $?"`，不用管道吞码。
- 报告：真机未验证；`settingsPage` 占位页样式为最简实现，视觉打磨留后续。

# iOS 本地模式完整隐藏 — 设计

日期：2026-11-15
分支：`dev/ios-hide-local`
输入：[2026-11-15-ios-本地模式隐藏可行性评估.md](2026-11-15-ios-本地模式隐藏可行性评估.md)（下称"评估"）
前置：Task 2/3 已隐藏设置页两处瓦片与概览卡 footer，已门禁两条引擎启动路径（见 [2026-11-13-ios-实施记录.md](2026-11-13-ios-实施记录.md)）

## 意图与为什么

iOS 版是纯远程客户端，本地 DSH（PRoot）在 iOS 上不可能运行。此前只隐藏了部分入口，"本机"仍会从主机切换器、聊天空状态、外链路由等多条路径漏进界面，让用户看到点了没反应的本地功能。本设计把评估 §8 的范围落地：**完整隐藏 iOS 本地专属入口 + 统一"未选择主机"状态 + 拦截直接页面跳转**，为将来分阶段删除建立清晰边界。

## 目标

1. iOS 上任何路径（菜单、空状态、搜索、外链、插件跳转、抽屉、网页模式）都不出现本地安装/启动/修复/手机操控入口。
2. 当前主机为 local（全新安装、旧偏好、删除主机、退出账号、关自动连接后重启五种来源）时，统一呈现"未选择主机 → 远程连接引导"，不闪现、不回落本地页。
3. 被禁页面（引擎、手机操控、本机安装等）经直接路由打开时被拦截，给出一致提示或回到远程入口，不出现"能打开但全坏"的页面。
4. state 层不再对 local 主机发起本地引擎连接尝试（评估未列全的补充，见"状态层"节）。
5. Android 行为零变化；远程共用能力（引擎参数、模型、会话、插件、诊断、主机管理）不受影响。

## 非目标

- 不删代码、不改 `HostKind`/`HostRef.local`/序列化编码、不迁移旧偏好（评估 §5.3、§8）。
- 不动 wire 契约。
- 不做真机验收（本机无设备，模拟器验收另排）。

## 反目标

- 按"引擎"关键词批量隐藏——引擎参数等对远程主机生效，误伤即破坏核心功能。
- 只藏 UI 不管操作层——用户仍能从外链进入坏页面。
- 把手机操控绑到"本地引擎"开关上——它是独立的平台能力。

## 约束

- 门禁基建沿用 `isIosProvider`（可 override，widget 测试注入）。
- 验证手段：`flutter analyze` + `flutter test`（widget 测试，桌面宿主）+ 模拟器构建；真机未验证如实标注。
- 硬规则：入口文案若需新增（"未选择主机"等），中英 ARB 同步后跑 `l10n_merge.py`。

## 方案（已定）

采纳评估 §5 的三层结构，外加状态层补充：

1. **统一能力判断**（评估 5.1）：新增 `localEngineSupportedProvider`（默认 `!isIos`）与 `phoneControlSupportedProvider`（默认 `!isIos`，独立开关）于 `lib/state/platform_state.dart`。菜单、搜索、路由、操作入口共用，替代散落的 `isIosProvider` 直读（现有三处门禁一并换成能力判断）。
2. **展示与访问同拦**（评估 5.2）：
   - 展示层：评估 §3 的 12 个入口逐个隐藏/替换（切换器本机行、标识、返回本机、聊天/抽屉空状态、本机网页、隐私页 OCR 区块、诊断跳转、搜索过滤、全部功能目录）。
   - 访问层：在 `settingsPageForLink` / `pageForId` 的**单一汇聚点**加能力门禁——被禁页面 id 解析为 null 或返回统一"不可用"占位，覆盖外链 `dshgo://open/*`、插件 `native_taps`、搜索历史、`HomeShell._openDestination`、直接构造 `LocalInstallPage` 的调用点。
   - 操作层：`openLocalInstall`、`EngineControl.ensureStarted`（已有）、`RuntimeBridge` 的 install/start/reset 等入口 iOS 时明确失败（不静默），复用既有错误码风格。
3. **统一未选择主机状态**（评估 §4 规则原样采纳）：等 `ActiveHostController.ready` 再判定；iOS 且 local → 显示"未选择主机"标识 + 远程连接引导（添加/登录/配对入口，不强制扫码）；保留设置入口；连接失败仍显示该远程主机可重试/切换；删除主机/退出账号回到同一未连接状态；原生与网页首页同规则；关自动连接不擅自连接。
4. **状态层补充**（本设计新增，评估未列）：`host.isLocal` 在 13 个非 UI 文件（`bots_state`、`notify_state`、`pet_signals`、`phone_turn_end`、`phone_skill_use`、`companion_signals`、`plugin_reload`、`artifact_files`、`share_code`×3、`connection_state` 等）分支会驱动本地引擎连接/监听。iOS 上这些分支不得触发本地通道调用。处理方式逐点判断：优先在连接汇聚点（`connection_state` 对 local 主机的连接建立）单点短路，其余按调用链自然熄灭；确实无法单点的才逐处加能力判断，并在计划里逐个列明谁置位谁清除。

## 涉及文件（预估）

新增：`platform_state.dart` 两个 provider、`ios_local_visibility_test.dart`（扩展）、连接引导复用现有 `RemoteScreen`/配对页。
修改（约 15-20 个）：`host_switcher.dart`、`remote_screen.dart`、`chat_screen.dart`、`sessions_drawer.dart`、`local_web_screen.dart`、`privacy_page.dart`、`diagnostics_page.dart`、`settings_search_page.dart`、`settings_pages.dart`、`page_links.dart`、`feature_catalog.dart`、`native_taps.dart`、`home_shell` 目的地构造、`hosts_state.dart`（ready 暴露/展示态）、`connection_state.dart`（local 短路）、`platform_state.dart`、既有三处 `isIosProvider` 改读能力 provider、ARB×2（如需新文案）。

## 验收标准

评估 §6 全单采纳，另加两条：

- iOS 上五种 local 来源（全新/旧偏好/删主机/退账号/关自动连接重启）逐一验证呈现同一未连接引导，且 `ready` 前不闪配对页。
- state 层：widget/单元测试断言 iOS 上无对 `dsh/runtime`、`dsh/phone` 通道的调用（沿用 `ios_boot_degrade_test` 的 RecordingRuntime 手法）。
- Android 回归：现有 `root_gate_autostart_test` 等本地路径测试不改而全绿。

## Builder check 裁决（2026-11-15，fresh reviewer 提出 4 问，均自决）

- **Q1 验收范围**：取"不发起本地引擎安装/启动/连接尝试"，非字面零通道调用。冷启动 `runtime_state` 对桩的一次 `status()` 轮询可接受（桩回安全默认值，Dart 容错）；门禁 `status()` 轮询牵动所有 `watch(localRuntimeProvider)` 分支，超出本阶段。voice/诊断发布同理不逐个门禁。
- **Q2 门禁落点**：builder 核实 `settingsPageForLink` 有旁路（`openSpot→spotPage→settingsPage()` 覆盖搜索历史/结果；`pageForId` 目录分支走 `item.native`/`item.action`）。门禁下沉到 `settingsPage(SettingsPageId)` switch 表 + 功能目录 item 查询两处真单点，配合被禁 id 清单；被禁页解析为 null 时复用 LinkRouter 既有"无法打开链接"兜底（`app_links.dart:308`），不新增文案。
- **Q3 展示面完备集**：按清单收口（评估 §3 十二项 + 既有三处门禁），共享页面 host=local 的退化 UI 由统一"未选择主机"状态兜住；不做行级审计（留待删除阶段）。
- **Q4 ready 前形态**：沿用现有启动画面盖住（`root_gate` 已等 settings/runtime/prefs loaded）；`LaunchController.ready(waitsForEngine:)` 在 iOS 恒 false。widget 测试通过 override `ActiveHostController.ready` 区分"ready 前"与"ready 后 local"两帧。`hosts_state.dart` 的 ready 已是公开 getter（`Future<void> get ready`），文件清单中"ready 暴露"一项不需要。
- 另：设计原写"13 个非 UI 文件"不准，实际 `isLocal` 分支散在 20+ 文件（含 `chat_state`、`providers_state`、`plugin_config`、`seat_planner` 等）；逐点归属仍按"留给执行者"处理，优先在 `localConnectionProvider`/`ensureStarted` 单点短路。

## 留给执行者的判断

- 各空状态"未选择主机"文案的具体措辞（中英同步）。
- 被禁页面 id 清单的最终枚举（以 `SettingsPageId` + `feature_catalog` 为准逐个判定归属，不凭名字猜）。
- 操作层失败提示的错误码与 UI 呈现细节。
- 状态层 13 个文件里哪些能被连接汇聚点单点覆盖、哪些需要逐处门禁——按调用链证据决定，宁可少加不可漏加。

## 实施结果（2026-11-15，分支 dev/ios-hide-local）

7 个任务全部完成，提交 `be0e27b..ba62dfc`（Task 1~6 + scheme 修复）。

**验收逐条**：
- 访问层门禁：`settingsPage()`/`settingsPageForLink`/`spotPage`/`openSpot`/`pageForId` 全链传两能力 bool；被禁页占位、链接解析 null 走 LinkRouter 既有兜底。路由测试 6 用例绿（含反向不误伤断言）。
- 展示层：切换器本机行、HostChip 标识（hostNameProvider 单点→"未选择主机"）、返回本机、后台运行/系统权限瓦片、隐私页 OCR 区块、诊断权限跳转行、聊天/抽屉空状态→ConnectGuideView、网页模式门禁。
- 五种 local 来源：统一走 ConnectGuideView；`ready` 前保持启动画面（activeHostReadyProvider gate）；连接失败仍显示该主机（_RemoteEmptyState 未被误路由）。测试 6 用例绿。
- 搜索/目录：`visibleSettingSpots`（入口行按 opens 判）、`featureCatalogBlockedIds={'phone'}`（web 条目远程有效不剔）；provider 无拦截时原样返回（seats identity 断言不破）。测试 4 绿。
- 状态层：`LocalConnectionController.build` 顶部短路；grep 证明 state 层无绕过 connector 的直调。测试 2 绿（running+有效地址场景，外部评审补漏的构造）。
- 回归：全量 1203 失败 vs 基线 1202，逐项 diff 新增仅 1 个（`update_retry_phase_test`，单跑 3 次全绿、update 模块本分支零改动、基线 0 次出现——判定并发 flaky）；消失项经重查为提取正则漏数字（`_005`），修正后消失项为 0。analyze 零 error/warning；l10n check 过；模拟器构建通过。
- 真机 iOS：未验证（本机无设备）。

**实施期新发现（计划外）**：
- Xcode 26 打开工程会重写 `Runner.xcscheme`（version 1.3→1.7、Launch 配置 Debug→Release、LLDB→PosixSpawn），重写后 `xcodebuild` 解析不出模拟器 destination，`flutter build ios --simulator` 报 "No Xcode build settings"。回退 scheme 到模板版恢复构建（`ba62dfc`）；签名配置在 pbxproj 不受影响。**再开 Xcode 可能再次重写，构建再挂就先回退该文件。**
- `openLocalInstall` 返回 `Navigator.push` 的 future（页面 pop 才完成），测试不能 await，否则挂起——用 unawaited+catchError。
- 计数闭包 `() => calls` 只读不增，会让"零调用"断言假通过——`() => calls++`。

## 终审结果（2026-11-16）

Fresh reviewer 审整分支（40 文件）：无 Critical；Android 零回归、远程共用能力未误杀、ready 门控无竞态均获确认。4 Important + 3 Minor，Important 全部修复（提交 `abba6f5`，6 用例 RED→GREEN）：

- I-1 抽屉主机图标在 iOS+local（即"未选择"状态）打开本地引擎页 → 改开远程主机页；快捷面板引擎项随能力剔除（含自定义列表，M-3）
- I-2 权限页「访问手机文件」开关在 iOS 触发未处理 MissingPluginException、「手机操控确认」行通向占位页 → 「手机」卡整卡隐藏
- I-3 BlockedFeaturePage 是被推路由里的无出口裸页 → 改走 AppPage 框（可返回）
- I-4 聊天空状态显示"引擎未连接"（本产品没有引擎）→ 未选择主机时给远程引导 pill
- M-1 主机状态行"未安装"外泄 + hostNameProvider 直读平台 → 状态显示"未连接"、契约统一读能力 provider
- M-2（保留）：pbxproj 的 DEVELOPMENT_TEAM/objectVersion 是用户 Xcode 配签名的产物，随提交入库，无害

修复轮回归：受影响面 293 失败逐项对基线零新增；analyze 零 error/warning。真机 iOS 仍未验证。

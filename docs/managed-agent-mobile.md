# Xcodex 插件托管 Agent 手机适配

## 范围与基线

2026-11-19，iOS 基于 `feat/orca-mobile-link` 的 `d129941f08f7e3884398b1d0ceb5a36b756d3dd3`，本次修改位于 `feat/xcodex-managed-agents`。
Android 和 iOS 按同一 DSH Remote 协议适配电脑上的 Xcodex 插件托管会话。
iOS 已有的直连 Orca 通道保留；它不是本次插件托管通道，不共用创建协议。
不迁移其他 Agent 历史，不重写登录、设备配对或中继，不修改线上服务配置。

## 协议契约

- `managedAgent/agents` 返回 `items`，每项含 `id/name/icon/agentId/registered/availability/capabilities`；旧 `available` 只表示已注册，不能解释成 CLI 已安装或鉴权成功。`availability: unverified` 表示实际可运行性在启动时确认。
- `managedAgent/create` 传 `workspaceId/agentId/operationId`。工作区必须来自当前 Host；同一创建请求重试复用 operationId，避免断线重复创建。
- 原生 DSH 新建仍调用 `session/create`。旧插件不支持发现时应保留 DSH 功能，不把网络错误伪装为空 Agent 列表。
- 会话身份只认 `projections.values.managedAgent.agentId`，不能根据模型名字或标题猜测。列表和 follow 快照都应携带该投影。
- 托管会话读取自己的 `session/modelCatalog`；模型和推理强度取电脑实际返回目录，不硬编码模型名。监听 `llm/models-updated` 清理缓存；不改变原生 DSH 全局目录语义。
- 聊天、审批、历史、标题事件沿用 `session/*` 与 `$events`；模型摘要标题由插件生成，手机显示和同步。
- 重命名、归档和恢复按会话能力使用现有接口。归档可恢复，不是永久删除。

## 能力边界与界面

能力字段按插件实际实现读取：`textPrompts/imagePrompts/fileAttachments/steering/queueWhileBusy/modelSelection/reasoningEffort/rename/archive/unarchive/pin/move/fork/rewind/compact/threadGoal/contextUsage`。
未声明的高级能力不启用；能力字段缺失的旧插件只使用已确认的兼容基础流程。

当前托管通道不支持图片、文件附件、执行中插话/排队、置顶、移动到另一工作区、分叉、回退、上下文压缩、线程目标、完整上下文用量、永久删除和权限模式切换。客户端不得仅因原生 Host 支持某接口就对托管会话调用。

- 单项及批量操作都要检查能力。批量置顶跳过不支持的托管会话；永久删除在 UI 和执行层双重拦截，混合批次仅原生可删除项执行。
- 归档搜索里的恢复入口按 `unarchive` 能力启用，托管不支持的永久删除入口隐藏。
- 自定义侧栏文件夹是手机本地分类，不等于改变 Host 工作区归属，可继续使用。
- 会话详情的目标/计划展示是只读，不代表允许新建或修改线程目标。
- 底层 CLI 自身具备能力不等于插件已经接通。未知投递结果不可自动重复发送。

## 验证与待办

iOS 应用定向回归 27 项通过；SDK 契约 6 项、加密隧道 1 项及原有 Orca 连接 3 项通过。本次修改的应用 Dart 文件静态分析无问题。插件后端/网关定向测试 36 项通过，插件 TypeScript 类型检查通过。
生产服务器仅执行顺序检查：测试进程最多绑定两个 CPU 核心，nice +15，进程树内存上限取 4 GiB 和启动时空闲内存三分之一的较小值；不足 4 GiB 系统可用内存或超过 10 分钟即终止本次测试进程。未停止已有服务、未运行全量构建。

验证环境为 Linux、Flutter 3.47.7 / Dart 3.13.5。现有 SDK 固定的 test_api 与上游 lockfile 不一致，因此应用检查使用临时兼容解析（Android 1 个、iOS 6 个测试依赖版本变化），完成后已恢复原 lockfile，没有提交依赖降级。正式锁定依赖构建仍须在匹配 SDK 的构建机验收。字体使用服务器已有 Noto 字体目录。此结果不代表原锁定依赖的正式安装包已构建通过。

新建操作 ID 在进程内按账号/Host/工作区/Agent 保留，网络恢复后的显式重试复用；不自动重发。App 被杀进程后的未确认创建尚未实现持久化恢复，列为后续增强。

待真实 Android/iPhone/iPad 与真实电脑验证：

- 同工作区新建 DSH、Claude Code、Codex，Logo 与工作区归属准确。
- 显示电脑实际模型目录和真实支持的推理强度；更换 Host、会话和断线后不串缓存。
- 两端接回同一会话、双方消息与摘要标题可见、审批允许及拒绝。
- 执行中按钮按能力控制；附件和不支持操作不发送 RPC。
- 归档恢复、重启后直达会话、断线恢复不重复创建或重复发送。
- 撤销单设备后不能读写，其他设备和在执行任务不受影响。
- 旧插件兼容以及 iOS 原有 Orca 通道回归。

未构建发布 APK/IPA，未进行真机或真实账号验收，未部署服务。

图标来源：沿用 Xcodex 插件 `packages/plugin/client/icons.ts` 的 GPT 图标及 Claude 放射标记；目录分组不显示 Agent 头像。

## 2026-11-23 新建入口补齐

侧栏、聊天顶部与文件夹内新建统一使用 Agent 选择器。文件夹入口把 folderId 传入创建流程，在 Host 返回会话并刷新列表后保存手机本地文件夹归属，再进入对话；工作区归属仍由 Host 管理。非 Remote 插件连接继续沿用各自原有创建流程。

选择器补充未连接、Agent 列表为空、工作区未就绪和无工作区提示，并提供工作区管理入口；离线时禁止托管创建。保留旧插件的 DSH 新建和 operationId 重试语义。补回既有登录文案缺失的 ARB 源条目，避免生成文案时丢失原有登录文字。

验证：修改文件静态分析通过；`managed_agent_creation_test`、`managed_creation_test`、`managed_composer_test`、`managed_send_guard_test`、`drawer_state_test` 共 30 项通过，文案检查和 diff check 通过。检查使用 Flutter 3.47.7 / Dart 3.13.5，本地临时兼容解析调整 6 个测试依赖，原锁文件已恢复；不代表原锁文件的正式构建验收。检查串行、最多单核，内存不超过空闲三分之一且最多 4 GiB。未构建 IPA、未发布、未进行真机与真实 CLI 联调。

## 2026-11-23 空白对话首页入口修复

“今天想做点什么？”首页此前只渲染 DSH 预设、权限与文件夹选项，不经过侧栏/顶部的新建按钮，因此不会显示 Agent 选择。这是此前新建入口补齐遗漏的路径，iOS 同样受影响。

`NewChatOptions` 在 Remote 插件连接且尚无会话时显示“选择 Agent”，打开现有选择器，支持 Claude Code / Codex 并传递当前待归属文件夹；选 DSH 保留首页，不提前创建会话。已存在会话不提供切换入口，其他连接方式保持原流程。

修改文件静态分析通过；首页入口、模式权限、托管创建与流式列表相关回归共 45 项通过，包含从实际 ChatScreen 首页点击并选择两种 Agent 的测试。测试串行，CPU 与内存预算各按启动时空闲资源的三分之一设置；使用本机兼容依赖解析，原锁文件已恢复。未构建安装包、未做真机验证。

## 2026-11-23 首页选择延迟到首条消息创建

首页 Agent 按钮显示当前选择（DSH / Claude Code / Codex）。选择托管 Agent 后仍留在空白首页，保留草稿和所选工作区；发送首条消息时才创建对应会话。切回 DSH 恢复预设和权限选项。托管 Agent 不应用原生 DSH 的预设、权限及待选模型；首页隐藏相应控件、原生斜杠命令和媒体生成入口。若草稿已有附件，提示移除或切回 DSH，不提前创建会话。

创建失败保留草稿与选择，沿用 operationId 显式重试机制。选择按账号/Host 隔离，离开已有会话重新新建时重置。已存在会话不能切换 Agent；侧栏/文件夹新建入口继续沿用原创建流程。

验证：修改文件 `flutter analyze --no-pub` 通过，首页选择、模式权限、托管创建、发送保护及流式列表等 8 个测试文件共 50 项通过，文案生成检查与 `git diff --check` 通过。两端串行检查，CPU 与内存预算各取启动时空闲资源三分之一，并监控资源变化；结束后释放测试进程。使用 Flutter 3.47.7 / Dart 3.13.5 的临时兼容依赖解析，已恢复原锁文件；未构建 APK/IPA，未做真机验收。

## iOS 新对话首页与 Agent 选择

侧栏、侧栏文件夹和聊天页右上角的「新对话」都进入同一张空白首页。首页的 Agent 按钮打开选择面板，DSH 与主机已注册的托管 Agent 使用相同的选项样式。工作区在首页选择，文件夹入口继续保留首条消息的本地文件夹归属。

选择 Claude Code 或 Codex 后，手机按当前主机、工作区和 Agent 调用 `managedAgent/create` 准备空会话。界面仍停在首页，右上角通过该会话的 `session/modelCatalog` 读取主机实际支持的模型与推理强度。切换工作区或 Agent 后使用新选择对应的目录。连接恢复或重试同一创建请求沿用 operationId。

首条消息复用准备好的 sessionId。用户显式选择模型时，先等待 `session/selectModel` 成功，再发送消息；失败时保留输入。主机按是否已有用户消息标记 blank，手机历史列表沿用已有过滤规则。原生 DSH 继续使用自己的目录和新建流程。

验证：修改文件 `flutter analyze --no-pub` 通过；首页选择与 Agent 选择、托管创建面板、延迟创建及 operationId 复用共 3 个测试文件 12 项通过（`home_agent_picker_test` 5 项、`managed_agent_creation_test` 5 项、`managed_creation_test` 2 项）。`git diff --check` 通过。检查使用 Flutter 3.47.7 / Dart 3.13.5，串行执行，CPU 与内存预算各取启动时空闲资源三分之一；结束后释放测试进程。未构建 IPA、未做真机验收。

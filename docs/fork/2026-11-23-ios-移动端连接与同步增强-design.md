# iOS 移动端连接生命周期与同步增强设计

## 范围与基线

2026-11-23，基于 `main` 的当前代码。本设计只针对 iOS App（`Xagent-IOS`），
Android 端共享同一套 Flutter 连接代码，按同一设计分阶段跟进。
不更换 DSH 通信协议，不重写 Noise 加密、Relay、P2P、Mux、seq 增量事件机制。

设计目标一句话：**即使底层连接断开、切换、被系统挂起，用户的会话、任务和操作
状态仍然连续可靠**——不追求物理连接永久在线，追求逻辑会话持续在线。

## 现状与问题定位

现有数据面质量不低：端到端加密到位（Server 只转发密文），增量同步协议严谨
（snapshot 游标 + 严格连续 seq + 缺段 `session/page` 补齐 + 重连 resync +
assistant revision 防丢）。缺的是移动端系统级能力。

| 问题 | 优先级 | 影响 |
| --- | --- | --- |
| iOS 后台连接中断，无任何保活 | P0 | 无法持续接收 Agent 状态 |
| 聊天记录无本地持久化（仅内存 `ChatRowsCache`） | P0 | 打开会话依赖 Host 在线与网络 |
| 双层重连竞争，外层最多 8 次即放弃 | P0 | 重连行为不可预期，前台也会死 |
| 回前台恢复依赖 kick 探测，无即时恢复路径 | P0 | 用户要等待才能继续操作 |
| 无系统级通知（任务完成/审批/失败） | P1 | 后台时收不到关键事件 |
| Host 在线与 Agent 忙碌不区分，忙时跳过健康探测 | P1 | 慢链路死链检测最长约 75 秒 |

已确认可复用的既有能力（本设计不重复建设）：

- `session/prompt` 已携带 `requestId`（uuidV4），Host 端按 requestId 幂等
  （session_api.dart 注释："Retrying with the same requestId is idempotent"）。
  可靠消息投递只需**客户端把 requestId 落盘**，Host 协议不改。
- `ConnectionDiagnostics` 已记录 phase/step/attempt/attempt/network（RTT、
  connectDurationMs、fallbackReason、iceProtocol），缺的是各阶段耗时分解。
- 增量同步的 gap repair 与 resync 机制完整，缺的是把 `_lastSeq` 游标从内存
  搬到本地存储。

## 设计原则

1. **Local-first 渲染**：界面展示不依赖实时网络。打开会话先读本地库即时展示，
   后台异步连 Host 增量同步刷新。
2. **Host-authoritative 同步**：电脑端始终是业务数据权威来源，本地库是缓存，
   冲突以 Host 为准。
3. **Connection-independent 会话**：业务会话生命周期独立于物理连接。连接断开、
   重建、路径切换对用户透明。
4. **正规 iOS 后台能力**：不绕系统。不用无声音乐、伪 VoIP、高频静默推送、
   高频后台任务做保活（审核风险 + 电量）。APNs 只做事件驱动通知，不做心跳。

## 模块划分

新增或改造四个模块，保留现有架构：

| 模块 | 职责 | 主要落点 |
| --- | --- | --- |
| Connection Lifecycle Manager | 统一连接状态、single-flight 重连、前后台切换、网络变化即时验证 | `relay_backend.dart`、`tunnel_carrier.dart` |
| Local Store | 本地持久化消息、会话、同步游标、outbox | 新增 Drift 数据层 |
| Sync Engine | 游标恢复、事件补偿、事务一致性 | `session_api.dart` `_SessionWatch` 扩展 |
| Notification Dispatcher | Host 关键事件 → APNs 分发 | Server 签发 + App 原生桥接 |

## 一、连接生命周期管理

### 1.1 统一重连决策者

现状：`RelayHostLink._run`（外层循环，`Backoff` 1s→30s、最多 8 次）和
`RemoteTunnelCarrier`（内层，自管 session、health、failure）是两套独立重连，
互相不知道对方在退避，失败计数各自叠加。外层耗尽后即使内层还能恢复，链接也
已 `failed`。

改造：单一 Connection State Machine，传输层只报告故障，上层做唯一重连决策。

| 当前行为 | 目标行为 |
| --- | --- |
| 两层独立重连、计数叠加 | Single-flight：一次只有一条重连路径，旧 attempt 的回调按代际丢弃 |
| 外层最多 8 次后放弃 | 前台且有网络时无限退避（封顶 30s + jitter）；仅明确不可恢复错误（身份被替换、信任失效、登出）才终态 |
| 回前台靠 kick 探测 | 回前台立即主动验证旧连接，1–2s 超时判定，失败即刻重建，不等心跳 |
| 网络变化触发 kick | 网络变化立即验证或重建 |
| 直连协商失败后才落 Relay | Relay 快速建立先保障可用，直连后台协商，择优热切换 |

### 1.2 心跳与超时参数

初始值，后续按真机弱网测试调，不写死：

| 参数 | 当前 | 建议初始 |
| --- | --- | --- |
| 传输层心跳间隔 | 25s | 15–25s |
| 心跳失效判定（3 倍） | 约 75s | 30–50s |
| 回前台主动探测超时 | 无 | 1–2s |
| 业务健康探测间隔 | 25s | 20–30s |
| 重连退避 | 1–30s | 0.5–30s + jitter |
| 用户操作触发重连 | 无明确路径 | 立即 |

连接检测结合实际业务流量：有正常数据帧传输时不额外发心跳。区分 **Host 在线**
（传输层可达）与 **Agent 忙碌**（Host 忙时业务探测跳过的现状要修正为：健康
探测走独立通道，不因 Agent 执行任务而跳过传输层心跳）。

### 1.3 传输路径优化（P2）

Relay 长连作为永久控制平面不拆；LAN/P2P/TURN 直连作为可选数据平面叠加，
路径切换只换数据通道，加密会话、follow 流、seq 游标全部保留。目标：Wi-Fi↔蜂窝
切换是无缝的，不是断线重连。落点 `relay_transport.dart`，改动面大，排在持久化
之后。

## 二、本地持久化（Local Store）

技术选型 SQLite + Drift。数据库配置文件保护，密钥用 Keychain 管理，退出账号
清除缓存。现有 `ChatRowsCache` 保留为 UI 渲染缓存，不再是消息的唯一客户端缓存。

### 2.1 表设计

| 表 | 内容 |
| --- | --- |
| `hosts` | 主机信息、最后在线状态 |
| `sessions` | 会话标题、类型、任务状态 |
| `messages` | 用户消息、Assistant 回复 |
| `session_events` | Tool Call、工具结果、审批、状态事件 |
| `sync_cursors` | 每个会话最后持久化 seq、assistant revision、日志代际 |
| `outbox` | 尚未确认送达 Host 的操作（requestId 为主键） |
| `attachments` | 文件/图片本地缓存索引 |

### 2.2 打开会话流程

现状：打开 App → 连接 Host → 拉 Snapshot → 解析构建消息 → 显示。

目标：打开 App → 读本地 SQLite 即时显示 → 后台异步连 Host → 游标恢复 + 增量
同步刷新 UI。电脑关机、手机无网时可读已同步历史。

## 三、持久化增量同步（Sync Engine）

不新增协议参数。现有 `session/follow`（snapshot + 事件流）+ `session/page`
（throughSeq/beforeSeq 分页）+ gap repair 逻辑正确，缺的是游标持久化。

流程：读本地游标 → 重连后 Host 给 snapshot → 若本地 seq 落后，用 `session/page`
按游标补齐缺段（现有 gap repair 已实现，改接到持久化游标）→ 订阅 live 事件 →
事件与游标同事务落盘 → 更新 UI。

一致性要求：

- 事件写入与游标更新同一数据库事务。
- 去重键：Host ID + Session ID + seq（日志代际变化触发全量 resync）。
- Replay 与 live 订阅之间不留遗漏窗口（现有 epoch 校验保留）。
- assistant revision 同样持久化。
- 会话删除、Host 日志清理能正确同步（以 Host snapshot 的 resident 列表为准）。

`afterSeq` 类的新协议字段是优化不是必需项，Host 不改协议。

## 四、可靠消息投递（Outbox）

Host 端幂等已存在（requestId），不需要新增。客户端侧：

1. 发送前先写 outbox（requestId + 内容 + 状态 pending）。
2. 发出后收到 Host 确认（prompt 进入 inbox 的应答）才标记 delivered。
3. 断线重连后，outbox 中 pending 的条目用**同一 requestId** 重发——Host 幂等
   保证不重复执行。
4. 有时效性的操作（权限审批、取消任务）不自动重发，重连后先校验对应任务/审批
   状态仍有效才执行。

## 五、APNs 通知系统（P1）

事件驱动，不是心跳。链路：Host 产生关键事件 → Notification Gateway → APNs →
手机。推送不能解密（通道是明文），只带事件摘要或不透明事件标识，详情仍走加密
链路拉取，正文不进推送。

| 事件 | 推送策略 |
| --- | --- |
| Agent 正在输出 token | 不推送 |
| Agent 完成任务 | 可见通知 |
| Agent 请求权限 | 高优先级可见通知 |
| Agent 等待输入 | 可见通知 |
| Agent 执行失败 | 可见通知 |
| 普通会话状态变化 | 合并后静默推送（仅限有限唤醒做增量同步，不做保活） |
| Host 上下线 | 按用户设置 |

工程要求：token 更新、设备解绑、通知去重、开发/生产环境隔离。
落点：Server 签发推送凭据（Xagent 仓库）、App 注册 device token 上报（Xagent-IOS）。

## 六、可观测性

在现有 `ConnectionDiagnostics` 基础上补各阶段耗时分解，让"连接慢"可定位：
WebSocket 建立 / Noise 握手 / 直连协商 / Relay 转发延迟 / Host RPC 响应 /
snapshot 数据量 / UI 渲染，各自独立指标。不新建整套 tracing，扩展现有结构。

## 七、开发优先级

| 序号 | 内容 | 优先级 |
| --- | --- | --- |
| 1 | 本地消息持久化（Drift、会话缓存、离线读取） | P0 |
| 2 | 统一连接生命周期（状态机、single-flight、前台快速恢复） | P0 |
| 3 | 持久化增量同步（游标恢复、缺段补齐、事务一致性） | P0 |
| 4 | 可靠消息投递（outbox + requestId 重发，Host 幂等已就绪） | P0 |
| 5 | APNs 通知系统（事件分发、可见通知、静默增量同步） | P1 |
| 6 | 传输路径优化（Relay 快速建连、直连后台协商、路径热切换） | P1 |
| 7 | 后台执行增强（短时后台任务、系统新能力评估） | P2 |

## 八、验收指标

初始工程目标，不是当前实测数据：

| 指标 | 目标 |
| --- | --- |
| 本地历史消息首次展示 | ≤200ms |
| 正常网络回前台连接恢复 P95 | ≤2s |
| Wi-Fi/蜂窝切换后连接恢复 P95 | ≤3s |
| Host 离线时查看历史记录 | 支持 |
| App 被系统杀死后恢复会话 | 支持 |
| 断线后历史同步 | 优先增量，不重复全量传输 |
| 用户指令重复执行 | 幂等测试中为 0 |
| 已持久化事件丢失 | 故障恢复测试中为 0 |
| 关键任务状态通知 | 经 APNs 送达 |

故障测试场景（需真实 iPhone，模拟器不反映后台挂起与系统回收）：锁屏 30 分钟
解锁后自动同步；后台 24 小时历史可读且自动恢复；进程被杀冷启动恢复；Wi-Fi→5G
切换不重复执行；进电梯保界面不清数据；电脑休眠提示 Host 不可达；电脑重启校验
会话状态；Server 重启客户端自动恢复；Agent 长任务不因手机断线受影响；发送指令
时断网不丢失待确认状态；Agent 输出中断网恢复后补齐缺段；万级事件会话分页读取；
多设备并发操作最终一致；推送未送达时回前台仍完整同步。

## 边界

- 不重写 Flutter 客户端为原生；iOS 系统能力走原生桥接。
- 不改 DSH 线协议，不加新 wire format；`session/prompt` 幂等、`session/page`
  分页、`session/follow` 语义保持不变。
- 不采用绕过系统的保活手段（无声音乐、伪 VoIP、高频静默推送、高频后台任务）。
- Android 端共享连接代码与数据层设计，按同一阶段跟进，不在本设计内实现。

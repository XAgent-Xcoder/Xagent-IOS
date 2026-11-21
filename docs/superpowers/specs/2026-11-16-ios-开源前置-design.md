# AgentPort iOS — 开源前置工作 · 设计

日期：2026-11-16　状态：待批准

## 意图与为什么

这个仓库 `dsh-Go-ios` 是从上游 `ccch1mneyyy/dsh-go`（AGPL-3.0）复制 `app/` 和纯 Dart 的 `packages/dsh_client`、`packages/dsh_remote` 后做 iOS 远程客户端的二开版本。要把它开源（push 到公开 GitHub），需要做一批 AGPL 合规、归属披露、素材替换和发布卫生的工作，否则法律上别人不能复用、品牌/吉祥物美术处于无授权状态、私有服务端点误导二开者。本设计只覆盖**开源前置**，不涉及功能开发。

## 目标 / 非目标 / 反目标

- **目标**：仓库达到可 push 到公开 GitHub 的状态——AGPL 许可与声明齐全、品牌/吉祥物受限素材替换为自己的、关于页与 README 正确披露上下游、构建/签名/发布卫生完成。
- **非目标**：功能开发、iOS 本地引擎、协议改动。
- **反目标**：不全局替换 `dsh`（`dsh_app` 包名、`dsh/…` 通道名、协议字段、原作者版权注释全部保留）；不照抄上游 `ASSETS.md` 当授权（那只披露不解决授权）；不动 wire 契约。

## 约束

- AGPL-3.0 是上游许可证，派生作品沿用（AGPL §4、§13：源码可得，网络交互须提供源码副本）。push 到 GitHub 本身满足 §13"提供源码"。
- 上游 `ASSETS.md` 明确：品牌图形与吉祥物（Deepy、鲸娘、Star 贴纸、鲸鱼尾巴）版权归 DSH-TUI，**不在 AGPL-3.0 授权范围**；"如果你以修改版或衍生作品再发布，请换成自己的名称和素材"。
- 包名/通道名/协议字段不动；原作者版权注释保留。
- 本仓库只有 24 个 commit，提交历史里未发现凭据或受限素材大文件（已 grep 验证）。

## 方案（已定的取舍）

1. **保留 AGPL-3.0 + 补许可与声明**（选定）。上游是 AGPL，派生沿用；补 `LICENSE`、`THIRD_PARTY_NOTICES.md`。替代方案（改 MIT）不可行——上游代码是 AGPL，派生不能降级许可。
2. **受限素材：保留上游美术原样，README 披露 + 免责声明**（2026-11-17 用户决定，替代最初的"移除并换成自己的简单图标"方案）。品牌鱼尾、Deepy/鲸娘宠物包、Star 贴纸、鲸尾动画全部保留，不清理、不替换；README 写清素材版权归 DSH-TUI、不在 AGPL 范围、本仓库不主张权利也不担责任。正式公开发布前按 fork 条款联系 DSH-TUI 说明素材保留情况，如被要求移除则移除。最初"移除"方案被否——图标未定稿，且移除宠物包会连带砍掉伙伴小屋功能。
3. **关于页与 README 披露上下游**（选定）。关于页显示 AgentPort、维护者、上游来源与原作者、许可证入口；README 写清非官方二开、修改内容、构建步骤。

## 六个修改项的具体做法

### ① 许可证
- 根目录加 `LICENSE`：AGPL-3.0 全文（照搬上游）。
- 根目录补 `THIRD_PARTY_NOTICES.md`：与 `app/lib/ui/common/third_party_licenses.dart` 的声明逐包对齐，保留每个项目的原版权声明与派生关系；每个包只出现一次。
- **不**照抄上游 `ASSETS.md`（那只披露不授权）；素材部分在 ③ 替换后另行说明。

### ② 开源首页
- 根目录新建 `README.md`：写明"AgentPort 是基于 dsh-go 的非官方 iOS 二开版本"，附原作者 Xcoder 与上游链接（`github.com/ccch1mneyyy/dsh-go`）、本 fork 维护者与仓库链接、修改内容清单、构建步骤。
- 修 `app/README.md` 的过时内容：把"Dart 界面加 Kotlin 原生运行时层"改成 iOS Swift 通道的说明。

### ③ 替换受限素材（首版：移除 + 简单自有图标）
按上游 `ASSETS.md` 的清单逐项处理：
- **品牌鱼尾图形**：移除 `app/assets/brand/*.svg`；替换 `app/lib/ui/shell/brand_mark.dart` 与 `brand_glyph.g.dart`（由 `app/tool/make_brand_mark.py` 从 `assets/brand/` 生成）的引用，换成自有简单图标；iOS 启动图标 `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` 同步换。
- **Deepy 小鲸鱼宠物包**：移除 `app/assets/pets/deepy-whale/`，清理 `app/lib/pets/`、`app/lib/ui/pets/pet_sprite.dart` 等引用。
- **鲸娘宠物包**：移除 `app/assets/pets/whale-girl/` 及同代码引用。
- **求 Star 贴纸**：移除 `app/assets/star/star_whale.webp`，改 `app/lib/ui/star/star_prompt_dialog.dart` 的 `asset` 常量。
- **鲸鱼尾巴动画**：移除 `app/assets/whale/`（`whale_1..4.png`、`whale.json`），改 `app/lib/ui/chat/widgets/whale_tail.dart`（manifest 与 sprite 加载）与 `activity_strip.dart`、`empty_state.dart` 的引用。
- **清理死链**：`pack.json` 路径、`app/tool/make_pet_pack.py`、`app/tool/make_whale_sprites.py`、设置页的宠物入口等，确保无残留死链。
- **自有图标**：做一个简单的自有图标替换品牌图形与启动图标（设计放 ② 的 README 同目录或单独 `docs/assets/`）。
- **仓库留一份简短的"素材来源与替换说明"**（不必照抄上游 `ASSETS.md`），写明哪些位置换了、原版权方是谁。

### ④ 关于页面
- `app/lib/ui/settings/about_page.dart` + `app/lib/state/app_info.dart`：显示 AgentPort、维护者信息（你的 handle）、本项目源码链接；保留 dsh-go 原作者与上游来源；提供许可证入口（指向 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`）。
- `authorBilibiliUrl`、`authorXUrl`、`authorGithubUrl` 目前硬编码 `agent.xcodex.vip` / `x.com/Xcoder` / `github.com/Xcoder`，改成你的真实账号（见下方待定）。

### ⑤ 整理服务地址（**待拍板，先不动**）
分享托管（`go.dshtui.com`）、论坛（`forum.dshtui.com`）、插件市场（`dl.dshtui.com` + `api.dshfind.com`）三个第三方服务：保留 / 替换成自己的 / 移除，待定。
- 更新检查改自己仓库或关闭。
- 上游用量统计（`go.dshtui.com/api/usage/v1`）默认关闭。
- 自建中继 `agent.xcodex.vip`（`relay_backend.dart`、`hosts_state.dart`）保留。

### ⑥ 构建与发布
- **签名**：`app/ios/Runner.xcodeproj/project.pbxproj` 里 `DEVELOPMENT_TEAM = VLVNURL99M` 是硬编码的团队号，改为使用者自行配置（移除或注释 + 说明）。`CODE_SIGN_STYLE = Automatic` 保留。
- **环境说明**：补 `docs/` 或 README 的 macOS + Xcode + Flutter 环境要求与构建步骤。
- **提交历史**：已 grep 验证无凭据、无受限素材大文件；24 个 commit 干净，无需 history 重写。
- **安装包对应公开源码版本**：开源后打 tag（如 `v1.0.16`）对应公开源码。

## 待定（你的决策，决定 ④ 与 ⑤）
- ④ 维护者真实 handle：GitHub / X / Bilibili 用哪个账号替换 `Xcoder`？
- ⑤ 三个第三方服务的去留。

## 留给实施者
- 自有简单图标的样式（极简，能代表"AgentPort"即可，不要求原创美术）。
- `THIRD_PARTY_NOTICES.md` 的逐条措辞（参照 `third_party_licenses.dart` 的条目）。
- ⑤ 三项服务的处理细节（待你拍板后补进设计）。

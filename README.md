# AgentPort

AgentPort 是基于 [dsh-go](https://github.com/ccch1mneyyy/dsh-go) 的**非官方 iOS 二次开发版本**。它把 dsh-go 的 Flutter 客户端做成 iOS 远程客户端：iPhone / iPad 通过远程连接（配对 / 中继 / LAN 直连 / WebRTC）直连电脑上正在运行的 DSH 主机，在 dsh-go 的 Dart 客户端代码基础上进行修改，原生层用 Swift 实现 iOS 需要的少量通道。

> 本项目**不是** dsh-go 的官方版本，也不是 dsh-go 团队维护。它是社区二次开发，与 dsh-go 官方无任何隶属关系。

## 来源与署名

- **上游**：[dsh-go](https://github.com/ccch1mneyyy/dsh-go)（AGPL-3.0，原作者 [ccch1mneyyy](https://github.com/ccch1mneyyy)）
- **本仓库**：[Xagent-IOS](https://github.com/XAgent-Xcoder/Xagent-IOS)，维护者 [XAgent-Xcoder](https://github.com/XAgent-Xcoder)

按 dsh-go 的 fork 署名条款，本仓库在 README、应用「关于」页与发布页均标注主仓库与原作者。本 fork 是 dsh-go（AGPL-3.0）的衍生作品，派生代码保留上游版权与许可注释。

## 构建

1. 环境：macOS + Xcode + Flutter（与 dsh-go 相同版本线）。
2. 构建：

   ```bash
   cd app
   flutter pub get
   flutter build ios
   ```

3. 签名：见下文「签名」。

## 签名

`app/ios/Runner.xcodeproj` 的 `DEVELOPMENT_TEAM` 已移除硬编码值，`CODE_SIGN_STYLE` 为 `Automatic`。构建时在 Xcode 里选择你自己的开发者团队与描述文件即可。首次构建需在 Signing & Capabilities 里配置你的 Apple 开发者账号。

## 许可

- 代码：**AGPL-3.0**（[LICENSE](LICENSE)）。
- 第三方声明：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 品牌与吉祥物美术：见「受保护素材的保留与免责声明」。

## 受保护素材的保留与免责声明

dsh-go 的品牌标识（鱼尾）与吉祥物（Deepy、鲸娘）是 DSH-TUI（ccch1mneyyy）的自有形象，**不在 AGPL-3.0 授权范围内**。

本 fork 保留上游美术原样，**不做清理**：

- `app/assets/brand/` — 品牌鱼尾图形
- `app/assets/pets/` — Deepy 与鲸娘宠物包（伙伴小屋引用的 Live2D 模型）
- `app/assets/star/` — 求 Star 贴纸
- `app/assets/whale/` — 鲸尾动画

**版权与责任**：上述素材版权归 DSH-TUI 所有。本仓库仅披露其来源，不对其主张任何权利，也不承担责任；再分发或商用须另行取得 DSH-TUI 授权。按 dsh-go 的 fork 条款，正式公开发布前维护者会先联系 DSH-TUI 说明素材保留情况，如被要求移除，本仓库将及时移除或替换。

## 目录结构

```
dsh-Go-ios/
├── app/            Flutter 应用（iOS 远程客户端）
├── packages/       纯 Dart 包：dsh_client、dsh_remote、dartssh2
└── docs/           设计与实施文档
```

## 发布前须知

按 dsh-go 的 fork 条款，公开此衍生作品前，请先通过 dsh-go 的 Issues 或社区联系原作者 ccch1mneyyy，说明用途与计划，并在仓库说明、应用「关于」页与发布页标注主仓库与原作者。

本 fork 的运行时差异：应用内「求 Star」弹窗指向本 fork 仓库（上游已在「来源与署名」中引用）；匿名使用统计默认关闭（不向 `go.dshtui.com` 上报，构建时可用 `--dart-define=DSH_USAGE_ENDPOINT` 显式开启）。

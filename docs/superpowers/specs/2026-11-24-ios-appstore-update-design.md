# iOS App Store 更新机制设计

日期：2026-11-24　分支：main（用户要求直接在 main 上操作）

## 背景与目的

这个仓库是 `ccch1mneyyy/dsh-go` 的 iOS fork（`XAgent-Xcoder/Xagent-IOS`）。上游的 App 内更新机制是为 Android 设计的：从 GitHub Releases 和自建镜像下载 APK，做 SHA256 校验后用 PackageInstaller 安装。iOS 上 `dsh/update` 通道是通用桩（`app/ios/Runner/DshGoChannels.swift` 的 `stubChannelNames`），整套 APK 链路在 iOS 走不通——现在点"检查更新"最终会卡在"无兼容包"。

iOS 的更新只能跳出 App 走系统：检测新版本 → 提示 → 跳 App Store。本设计给 iOS 一条独立的轻量更新链路，并借此把指向上游仓库的常量换成自己的仓库。

## 目标

- iOS 上：检查更新（手动 + 启动自动检查）指向自己域名的版本端点，发现新版本时提供"在 App Store 中更新"入口。
- 把代码中指向上游 `ccch1mneyyy/dsh-go` 的仓库常量换成 `XAgent-Xcoder/Xagent-IOS`（上游要换；第三方致谢 `liguobao/ds-harness-remote` 保留不动）。
- Android 现有 APK 自更新链路行为不变。

## 非目标

- 不做 iOS TestFlight 直链分发（那是上架前的临时渠道，App Store 上架后不再需要）。
- 不动第三方致谢（`AppInfo.remoteProject`）。
- 不重构 Android 更新流程。

## 方案取舍

**选定的：独立 iOS 检查器 + UI 平台分支。** 新增一个只取"最新版本号 + 说明 + App Store 链接"的轻量检查器，UI 层按 `TargetPlatform` 分支：iOS 走新检查器并显示 App Store 按钮，Android 走现有流程。

没选的：复用现有 `UpdateChecker` 并给 iOS 加分支。现有代码深度绑定 APK 概念（asset、ABI、差分包、校验和、PackageInstaller、安装路由），硬塞 iOS 分支会引入大量用不上的状态和错误路径。

## 版本端点约定

`GET https://agent.xcodex.vip/ios/latest.json`（静态 JSON，域名的所有者手动发布）：

```json
{
  "version": "1.0.16",
  "build": 2,
  "notes": "更新说明（Markdown，可为空）",
  "appStoreUrl": "https://apps.apple.com/cn/app/xagent/idXXXXXXXXXX"
}
```

- `version`：语义化版本号，对应 `pubspec.yaml` 的 `version: x.y.z+build` 的前半部分。
- `build`：整数 build 号。新版本判定：`version` 更新，或 `version` 相同且 `build` 更大。
- `notes`：更新说明，展示在更新弹窗里；缺失时显示"无更新说明"。
- `appStoreUrl`：App Store 页面链接（上架后填入真实 ID；上架前填占位链接也可，按钮行为不变）。
- 失败处理：网络错误、404、JSON 解析失败都归为"暂时检查不了更新"，与 Android 的检查失败文案一致。

## 已安装版本来源

用 `AppInfo.version`（`String.fromEnvironment('DSH_APP_VERSION', defaultValue: ...)`），与 Android 侧 `AppInfo` 的既有约定一致。注意：现有 `defaultValue: '1.0.2+1'` 与 `pubspec.yaml` 的 `1.0.15+1` 不同步，实现时一并修正为 `1.0.15+1`，并保留"发版时手动同步"的既有约定。

## UI 行为

- **设置 → 关于 → 检查更新**（`checkForUpdates`）：iOS 上跑 iOS 检查器；有新版本显示弹窗（版本号、说明、"在 App Store 中更新"主按钮，用 `url_launcher` 打开 `appStoreUrl`）；已是最新显示"已是最新版本"。
- **启动自动检查**（`UpdateLaunchCheck`，启动 6 秒后的每日自动检查）：iOS 上同样生效，发现未跳过的新版本时弹同样的弹窗。跳过逻辑：弹窗提供"跳过此版本"，把跳过的版本号写入 `shared_preferences`，启动检查不再弹。
- **Android 弹窗**：不变。
- 弹窗内的版本号标题、文案走 l10n（新增 iOS 专用的字符串键，中英两套）。

## 上游常量更换

- `app/lib/update/update_config.dart`：`updateRepo` 从 `ccch1mneyyy/dsh-go` 改为 `XAgent-Xcoder/Xagent-IOS`。该常量同时驱动 GitHub API、releases 页、asset URL 和镜像改写逻辑（镜像改写按 repo 名匹配路径段），换名后 Android 自更新将查自己仓库的 Releases。
- `app/lib/state/app_info.dart`：`upstreamAuthor` / `upstreamRepo` / `upstreamRepoUrl` 指向 `XAgent-Xcoder/Xagent-IOS`（关于页与许可页的致谢行）。
- 第三方致谢 `remoteProject = 'liguobao/ds-harness-remote'` 不动。

## 留给实现者的决定

- 新检查器的文件布局（建议 `app/lib/update/ios_checker.dart` 之类的轻量文件 + 一个 Riverpod provider，不挂现有 APK 状态机）。
- 测试：端点 JSON 解析、版本比较（version 更新 / 同 version build 更大 / 无更新 / 畸形 JSON / 网络失败），以及跳过版本的读写；沿用项目现有测试风格。
- l10n 新字符串的具体措辞。

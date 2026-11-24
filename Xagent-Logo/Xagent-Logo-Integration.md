# Xagent Logo 开发接入

当前 iOS 项目已经接好。写新页面时，通常只需要导入组件。配套的 Xagent-Logo-Developer-Kit.zip 用于交接给其他项目。

## Flutter 页面

```dart
import 'package:dsh_app/ui/shell/brand_mark.dart';

// 图形高度 28 逻辑像素，宽度按原稿比例计算。
const leading = BrandMark(size: 28);

// 方形深色底板，适合关于页、设置页和二维码中心。
const appTile = BrandMark(size: 64, tile: true);

// 与定稿相同的上下组合，宽 144；字标按主题选择墨色或白色。
const hero = BrandSignature(width: 144);

// 单独使用转曲字标，适合欢迎页。
const name = BrandWordmark(height: 20);

// 紧凑横排，适合抽屉标题；跟随系统文字缩放。
const drawerBrand = BrandLockup(height: 19);
```

放到页面上可直接写 `Center(child: BrandSignature(width: 144))`。固定深色海报上可指定 `BrandSignature(width: 144, wordColor: Colors.white)`；单色页脚可用 `BrandMark(size: 18, color: Colors.grey)`。颜色常量的示例需要导入 `package:flutter/material.dart`。系统桌面使用无文字的方形图标，在页面中要展示你发来的完整设计时选 `BrandSignature`。

图形、字标和组合由 Flutter 原生路径绘制，可以任意缩放。已有调用继续从 `brand_mark.dart` 导入。运行时不需要注册 PNG、加载 SVG 或增加第三方依赖。

## 交接给另一个 Flutter 项目

1. 从压缩包的 `09_Flutter/` 复制 `xagent_logo.dart` 和 `brand_glyph.g.dart`，放在同一个目录，例如 `lib/brand/`。
2. 在页面导入 `../brand/xagent_logo.dart`（按页面位置调整）。该入口直接提供 `BrandMark`、`BrandWordmark` 和 `BrandSignature`；`BrandLockup` 是当前项目额外提供的抽屉与分享卡布局。
3. 系统桌面图标另走原生资源。Flutter 页面组件不会改变手机桌面图标。

## 原生资源与生效时机

| 场景 | 资源入口 | 接入方式 |
|---|---|---|
| 本仓库 iOS 桌面 | app/ios/Runner/Assets.xcassets/AppIcon.appiconset/ | Xcode 的 Runner 已选择 AppIcon。系统按 Contents.json 自动选尺寸。修改后重新构建并安装 App。 |
| 本仓库 iOS 冷启动 | app/ios/Runner/Assets.xcassets/LaunchImage.imageset/ | LaunchScreen.storyboard 居中使用 96 pt 的图标，提供 1x、2x、3x；随后由 Flutter 首屏接手。 |
| Android 桌面 | 包内 04_Android/res/ | 合入目标应用模块的 src/main/res/，在 application 标签设 android:icon="@mipmap/ic_launcher"。已有 android:roundIcon 时指向同一资源。接入前核对目标项目同名资源。 |
| 浏览器标签与主屏幕 | 包内 05_Web/ | 静态文件发布至 /brand/，将 head-snippet.html 中的标签合入页面 head；已有 manifest 的站点合并 icons。 |

## 后续换版

这里的绘制母版是 `design/Xagent-Identity-v1/01_Vector/mark/color.svg` 和 `wordmark/ink.svg`。保留 v1 的画板及绝对 M / L / Q / Z 路径约定时，在仓库根目录运行：

```sh
python3 app/tool/make_brand_mark.py
```

脚本刷新 Flutter 路径。若新版改变画板、底板、颜色或组合比例，同时更新组件布局和原生资源；现有 PNG、AppIcon 与网页导出文件均为发布快照。预览和印刷规范位于包内 00_Guide/。

## 在本机检查

普通 Flutter 环境中，从 app/ 目录运行品牌测试。项目根目录已配置测试字体时可使用以下命令；遵守项目的测试资源预算。

```sh
DSH_TEST_FONT_DIR="$PWD/../.dsh-test-fonts" flutter test --no-pub --concurrency=1 test/shell/brand_mark_test.dart
```

本次交付已刷新并复验浅色和深色品牌截图。iOS 桌面和系统启动画面需要重新安装构建产物才能验证；Flutter 热重载适用于应用内页面。

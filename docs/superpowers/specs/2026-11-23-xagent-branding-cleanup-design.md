# Xagent 品牌清理与 App Store 准备 — 设计文档

日期：2026-11-23
状态：待确认

## 意图与原因

本项目是 dsh-go 的 iOS 二次开发版（AGPL-3.0）。dsh-go 的品牌与吉祥物美术（鱼尾、Deepy、鲸娘）
**不在 AGPL 授权范围内**，版权归 DSH-TUI 所有，再分发或商用须另行授权（见仓库 README
「受保护素材的保留与免责声明」）。现在要正式上线 App Store，这些素材必须全部移除。
同时把 App 改名为 Xagent，使用现有的 X logo（青色 X + 深底，已存在于 AppIcon.appiconset）。

## 范围

**做**：
1. 删除 4 个版权素材目录：`assets/brand/`、`assets/pets/`（内置包）、`assets/star/`、`assets/whale/`
2. **同步删除 `pubspec.yaml` 里对应的 asset 声明**：`- assets/whale/`（145 行）、`- assets/pets/deepy-whale/` + `- assets/pets/whale-girl/`（155–156 行）、`- assets/star/`（158 行）。只删目录不改 pubspec 会直接构建失败。（`assets/brand/` 未在 pubspec 声明——鱼尾是编译期生成的矢量路径——无需删声明。）
2. 鱼尾品牌标 → 替换为 X 形矢量标（App 内所有 BrandMark 位置 + 图标选择器预览）
3. 鲸尾加载动画 → 替换为 X 形矢量动画（保留 4 档速度/交叉淡变的原有体验）
4. 内置宠物（deepy-whale、whale-girl）→ 删除，默认改为"不显示"，保留宠物导入框架
5. 求 Star 弹窗的鲸鱼贴纸 → 删除图片，保留弹窗框架（fork 条款允许的求 Star 行为保留）
6. 改名 Xagent：Info.plist（已改显示名）、CFBundleName、pubspec name、AppInfo.name/wordmark
7. 修复因上述删除而挂掉的测试

**不做**：
- 不删除宠物子系统框架（lib/pets/、lib/ui/pets/）——用户仍可自行导入宠物包
- 不删除求 Star 弹窗逻辑（star_prompt.dart、star_prompt_host.dart）——fork 条款允许
- 不删除 `tool/make_brand_mark.py` 和 `tool/make_whale_sprites.py` 生成器脚本
  （品牌标改 X 后，make_brand_mark.py 的输入没了，脚本本身留着无害；
  鲸尾改矢量后 make_whale_sprites.py 不再被使用，留着但标注废弃）
- 不改中继服务器、ATS、隐私权限键（App 无相机/麦克风/定位/蓝牙请求，无需 NS*UsageDescription）
- 不配 .xcprivacy 隐私清单（匿名统计默认关闭，首版不阻塞；后续按需补）
- 不做 App Store Connect 提交物料（隐私政策 URL、截图、支持网址——由用户准备）

## 约束

- 删除素材文件后，运行时加载这些文件的代码不能崩：
  - `WhaleSprites.load()` 读 `assets/whale/whale.json` → 改为矢量绘制，不再读文件
  - `StarPromptDialog.asset` 读 `assets/star/star_whale.webp` → 文件没了预缓存会抛未处理异常（star_prompt_host.dart:75 无 catch），`StarPicture` 会渲染坏图——必须同时修这两处，不是"静默失败"
  - `PetPack.load()` 读 `assets/pets/<id>/pack.json` → 内置 id 从 builtInPets 移除后不再被加载
- 生成代码 `brand_glyph.g.dart` 里的鱼尾矢量路径是**编译期常量**，不读 assets/brand/，
  所以删 assets/brand/ 不影响运行；但路径本身是鱼尾形状，必须换成 X 形路径
- AppIcon.appiconset 已是 X logo，不动

## 方案

### 鱼尾品牌标 → X 标（lib/ui/shell/brand_glyph.g.dart + brand_mark.dart）

`brand_glyph.g.dart` 是 `tool/make_brand_mark.py` 从 `assets/brand/*.svg` 生成的矢量路径。
现在把鱼尾路径替换为 X 形路径，使 `BrandMark` widget 在 App 内所有位置（设置页脚、关于页、
启动页、侧栏、分享卡、二维码、欢迎页）画出 X 而不是鱼尾。

X 形的几何参数（从 AppIcon 1024 图标实测）：
- 青色 X 包围盒 592×649 像素，宽/高比 ≈ 0.91
- 图标内 X 中心 (490.5, 470.0)，略高于图标中心 (512, 512)

`BrandMark` 的公开 API 不变（`size`、`color`、`tile`、`aspect`、`visualCentre`、`opticalShift`）。
`_BrandPainter` 改为绘制 X 形路径，而不是鱼尾的 body/fin/belly/bubble 四段。
颜色：沿用 `BrandGlyph` 里原有的浅色/深色两套调色板，但形状换 X。
`AppIconGlyph` 枚举和图标选择器的 `_IconPainter` 复用同一套路径，自动跟着变 X。

实现方式：不手写 SVG 路径，直接在 `brand_glyph.g.dart` 里用 `Path` API 画一个
对称的 X 形（两条对角线笔画交叉，带圆角端点），与 AppIcon 的 X 形一致。
`make_brand_mark.py` 保留但不再从 assets/brand/ 读取（文件没了），改为从内置 X 路径生成。

### 鲸尾加载动画 → X 动画（lib/ui/chat/widgets/whale_tail.dart）

`WhaleTail` widget 的公开 API 不变（`level`、`color`、`height`、`still`、`aspect`）。
内部从读精灵图 atlas（whale.json + 4 张 png）改为矢量绘制一个 X 形：
- X 形随 `level` 旋转（0–4 档对应不同旋转速度和角度）
- 交叉淡变逻辑保留（新旧两套 X 同时渲染，权重渐变）
- `WhaleSprites` 抽象类改为 `XMark` 矢量绘制器，不再读 assets/whale/
- 颜色常量 `deepSeekBlue`/`deepSeekBlueDark`/`whaleColorFor` 保留（X 用同色系）
- 空状态（empty_state.dart）的 `WhaleTail(still: true)` 照常工作

`make_whale_sprites.py` 保留但标注废弃（鲸尾改矢量后不再需要精灵图生成）。

### 内置宠物删除（lib/pets/pet_prefs.dart + lib/ui/pets/pet_picker.dart）

- `builtInPets = []`（从 `['deepy-whale', 'whale-girl']` 改为空列表）
- `builtInPets = []`（从 `['deepy-whale', 'whale-girl']` 改为空列表）
- `defaultPetId` 不能直接设成 `noPetId`：`adoptDefault()` 调 `setPack(defaultPetId)`，若它已是 `noPetId`，会写 `packExplicit=true`，把"还没选择"变成"显式不显示"，之后 `petEnabled` 切换时 `_load` 里 `!state.packExplicit` 的回落路径再也触发不了。改法：`defaultPetId` 保留一个内置 id 字面量（如 `'deepy-whale'`，仅作占位，素材已删、永不会被加载），或让 `adoptDefault` 在 `builtInPets` 为空时直接走 `noPetId` 且不置 `packExplicit`。推荐后者，语义更干净。
- `pet_picker.dart` 里 `builtInPets` 的显示项循环自然不显示（列表为空）
- 框架 `lib/pets/` 和 `lib/ui/pets/` 全保留，用户导入宠物包的功能照常
- `lib/ui/companion/companion_chrome.dart:792` 硬编码的 `petPackProvider('whale-girl')` 和
  `lib/dev/pet_actions_probe_main.dart` 里的 `'whale-girl'` 顺手清理（dev 调试入口，生产不跑）

### 求 Star 贴纸删除（lib/ui/star/star_prompt_dialog.dart）

- `StarPromptDialog.asset` 常量指向的 `assets/star/star_whale.webp` 删除
- `StarPromptHost._maybeShow` 里的 `precacheImage(AssetImage(StarPromptDialog.asset))` 
  在文件不存在时静默失败（`catch (_)`），弹窗其余内容照常显示
- 求 Star 弹窗框架（star_prompt.dart、star_prompt_host.dart、star_prompt_dialog.dart）保留
- 修复点：弹窗里的 `StarPicture`（star_prompt_dialog.dart:256，裸 `Image.asset`，无 errorBuilder）必须从 Column 里移除或换成不依赖该文件的占位，否则渲染坏图占位符；`star_prompt_host.dart:75` 的 `precacheImage` 没有 error handler，文件删除后会抛未处理的异步异常，需要包上 `whenComplete`/catch 或直接删掉这行预缓存

### 改名 Xagent

- `Info.plist`：`CFBundleDisplayName` 已改为 `Xagent`（未提交改动，保留）；
  `CFBundleName` 从 `dsh_app` 改为 `Xagent`
- `pubspec.yaml`：`name: dsh_app` 改为 `name: xagent`；`description` 从
  `"DSH — DeepSeek Harness on your phone"` 改为 `"Xagent — 远程 Agent 客户端"`
- `lib/state/app_info.dart`：`name` 和 `wordmark` 从 `'AgentPort'` 改为 `'Xagent'`
- `README.md` 和 `AGENTS.md` 里的项目名引用保持（README 已经用 AgentPort 做仓库名，
  不需要全改；但 App 内显示名必须是 Xagent）

### iPad（不处理，仅记录决定）

**不做任何 iPad 适配改动，代码全部保留。** 上架只支持手机是 App Store Connect 提交
时的配置（截图、设备类别），不是代码层面的删除。Info.plist 的
`UISupportedInterfaceOrientations~ipad`、project.pbxproj 的 `TARGETED_DEVICE_FAMILY` 等
iPad 支持全部原样保留。

### 测试修复

删除素材后，以下测试会挂（引用了被删的资产或被改的 API），需逐个修复：
- `test/chat/activity_strip_golden_test.dart` — 黄金图对比，鲸尾没了
- `test/access/access_pet_default_test.dart` — 默认宠物改了
- `test/pets/pet_pack_test.dart` — 内置宠物 id 没了
- `test/shell/brand_mark_test.dart` — 品牌标改了
- `test/pets/pet_pixel_test.dart` — 精灵图没了
- `test/pets/pet_mood_test.dart` — 情绪 reducer 可能引用内置宠物
- `test/pets/support.dart` — 测试 fixture 可能引用内置宠物
- `test/pets/pet_library_test.dart` — 用户宠物库，内置包删了
- `test/pets/overlay/overlay_channel_test.dart` — 覆盖层
- `test/pets/pet_parts_test.dart` — 宠物部件

修复策略：测试 fixture 里的内置宠物 id 换成 `noPetId` 或用户导入的模拟包；
黄金图测试重新截图；品牌标测试验证 X 形而不是鱼尾。

## 不做的事（明确排除）

- 不改 `app/ios/Flutter/AppFrameworkInfo.plist`（Flutter 框架文件，自动管理）
- 不改 `app/ios/Runner.xcodeproj/project.pbxproj` 的 Bundle ID
  （`com.xcoder.agentport.ios` 含 agentport 字样，但改 Bundle ID = 新 App，
  App Store Connect 里已建的 App 记录对不上，首版保持原样）
- 不改 `lib/ui/web/`（网页模式）和 `lib/ui/engine_settings/`（插件设置）里
  对 BrandMark 的引用——它们用的是 `BrandMark` widget，自动跟着变 X
- 不改 `packages/`（纯 Dart 包，不含 UI 素材）

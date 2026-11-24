# Xagent 品牌清理与改名 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 dsh-go 版权素材（鱼尾品牌标、鲸尾动画、内置宠物、求 Star 贴纸），品牌标与活动指示换成 X 形象，App 改名 Xagent，iOS 只支持手机。

**Architecture:** 四个版权素材各自是「资产文件 + 读取该文件的框架代码」。删除资产文件，同时把读取它们的框架代码改为不依赖该文件：鱼尾和鲸尾改成矢量 X 绘制（不再读 assets），内置宠物从 builtInPets 移除（框架保留用户导入），求 Star 的 Image.asset 换成矢量 X 徽章。改名涉及 pubspec 包名（dsh_app → xagent，牵动 ~1044 个 import）、CFBundleName、AppInfo。

**Tech Stack:** Flutter (Dart 3.13)，原生 iOS（Xcode project、Info.plist），flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-23-xagent-branding-cleanup-design.md`（本计划的依据，执行者须同时读它）

## Global Constraints

- **不删除宠物子系统框架**（`lib/pets/`、`lib/ui/pets/`）——用户仍可导入宠物包
- **不删除求 Star 弹窗逻辑**（`lib/state/star_prompt.dart`、`lib/ui/star/star_prompt_host.dart`）——fork 条款允许的求 Star 行为保留
- **保留** `tool/make_brand_mark.py`、`tool/make_whale_sprites.py`（鲸尾改矢量后 make_whale_sprites 标注废弃）
- **不改** Bundle ID `com.xcoder.agentport.ios`、`.xcprivacy`、中继服务器、ATS、隐私权限键
- **不改** `app/ios/Flutter/AppFrameworkInfo.plist`（Flutter 框架自动管理）
- **iPad 支持全部保留**（Info.plist 的 `~ipad` 段、pbxproj 的 `TARGETED_DEVICE_FAMILY`），上架只支持手机是 App Store Connect 提交配置，非代码删除
- **AppIcon.appiconset 已是 X logo，不动**
- X 形的几何基准（从 AppIcon 1024 图标实测）：青色 X 包围盒 592×649 像素，宽/高比 ≈ 0.91，X 中心略高于图标中心
- 提交信息遵循项目现有惯例（中文描述 + 不带 Co-Authored-By，除非用户要求）

## Review Focus

这些是 spec 暗示、但没有单一测试直接钉住的输入类/失败模式，最容易咬人：

1. **包名重命名 `dsh_app` → `xagent`**：~1044 个 `import 'package:dsh_app/...'` 必须全部改，漏一个 flutter analyze 就报。执行者用 sed 批量改后必须跑 `flutter analyze` 确认零 error。
2. **`defaultPetId` 不能直接设成 `noPetId`**：`adoptDefault()` 调 `setPack(defaultPetId)` 会写 `packExplicit=true`，把"还没选择"变成"显式不显示"，之后 `petEnabled` 切换时 `_load` 的 `!state.packExplicit` 回落路径失效。正确改法见 Task 3。
3. **求 Star 的 `precacheImage` 无 error handler**：删 `assets/star/star_whale.webp` 后，`star_prompt_host.dart` 的 `unawaited(precacheImage(...))` 抛未处理异步异常；`StarPicture` 的裸 `Image.asset` 渲染坏图占位符。Task 4 必须同时修两处。
4. **pubspec 声明的素材目录删除**：`assets/whale/`、`assets/pets/deepy-whale/`、`assets/pets/whale-girl/`、`assets/star/` 都声明在 pubspec.yaml，只删目录不改 pubspec 直接构建失败。Task 5 必须同步删声明。
5. **`companion_chrome.dart` 硬编码 `'whale-girl'`**：`CompanionPixelWhale` 直接 `petPackProvider('whale-girl')`，绕过 `builtInPets`，删内置包后仍会触发 `PetPack.load` 读已删的资产。Task 3 必须清掉。

---

### Task 1: X 品牌标（鱼尾 → X 矢量）

把 `brand_glyph.g.dart` 的鱼尾矢量路径换成 X 形，`BrandMark` 和图标选择器随之画 X。

**Files:**
- Modify: `lib/ui/shell/brand_glyph.g.dart`（全部重写）
- Modify: `lib/ui/shell/brand_mark.dart`（`_BrandPainter` 改为画 X）
- Modify: `lib/ui/settings/appearance/app_icon_picker.dart:266-276`（`_IconPainter` 画 X）
- Test: `test/shell/brand_mark_test.dart`

**Interfaces:**
- Consumes: 无（品牌标是底层，别的任务用它的 `BrandMark` widget）
- Produces:
  - `BrandGlyph.mark`：X 形 `Path`（取代 `body`/`fin`/`belly`/`bubble`）
  - `BrandGlyph.box`：X 的 ink box，`Rect.fromLTRB(...)`，`aspect` ≈ 0.91
  - `BrandGlyph.centroid`：X 中心（X 对称，等于 box 中心）
  - `BrandGlyph.tile`：保留原圆角方路径（AppIcon 的圆角轮廓，不变）
  - `BrandGlyph.tileBox`：保留原 `Rect.fromLTWH(18, 18, 72, 72)`
  - `BrandGlyph.tileFill`：保留原线性渐变（不变）
  - `BrandGlyph.xLight`/`BrandGlyph.xDark`：X 的渐变（取代 tail/fin/belly/bubble 四个渐变）

- [ ] **Step 1: 写失败测试**

`test/shell/brand_mark_test.dart` 的 `generated glyph data matches its paths` 测试改为验证 X 的几何：`mark` 的 ink box 与 `BrandGlyph.box` 一致，`centroid` 等于 box 中心，`aspect` 约 0.91，`visualCentre` 的 dx/dy 都接近 0.5（X 对称）。其余测试（sizes、lockup、golden sheet）保持结构，golden 留到 Task 7 重新生成。

- [ ] **Step 2: 运行测试确认失败**

`flutter test test/shell/brand_mark_test.dart`
预期：FAIL（`BrandGlyph.mark` 还不存在）

- [ ] **Step 3: 重写 `brand_glyph.g.dart`**

用 `Path` 画一个 X：两条对角线笔画交叉，带圆角端点。X 在 108 grid 里居中，宽/高比 0.91。`box` 是 X 的 ink box，`centroid` 是 box 中心，`aspect` 是 box 的宽/高。`tile`、`tileBox`、`tileFill` 原样保留。`xLight`/`xDark` 是 X 的渐变（浅色页用蓝紫渐变，深色页用提亮版）。文件头注释改为说明这是 Xagent 的 X 形标，由手工维护（make_brand_mark.py 不再从 assets/brand/ 读取，文件没了）。

- [ ] **Step 4: 改 `brand_mark.dart` 的 `_BrandPainter`**

`_Style.mono` 画 `BrandGlyph.mark` 单色；`_Style.light`/`_Style.dark` 画 `mark` 加 `xLight`/`xDark` 渐变；`_Style.tile` 画 `tile` 圆角方加 `tileFill`，再画 `mark`。`BrandMark.aspect` 改用 `BrandGlyph.mark` 的 box 宽/高。`visualCentre` 现在 ≈ (0.5, 0.5)，`opticalShift` 接近零。

- [ ] **Step 5: 改 `app_icon_picker.dart` 的 `_IconPainter`**

`AppIconGlyph.mono` 画 `BrandGlyph.mark` 单色；`glassDark`/`glassLight` 画 `mark` 加 `xDark`/`xLight` 渐变。删掉对 body/fin/belly/bubble 的引用。

- [ ] **Step 6: 运行测试确认通过**

`flutter test test/shell/brand_mark_test.dart --name "generated glyph data"`
预期：几何断言 PASS（golden sheet 测试仍会挂，留到 Task 7）

- [ ] **Step 7: 提交**

```bash
git add lib/ui/shell/brand_glyph.g.dart lib/ui/shell/brand_mark.dart lib/ui/settings/appearance/app_icon_picker.dart test/shell/brand_mark_test.dart
git commit -m "品牌标从鱼尾换为 X 矢量，App 内所有 BrandMark 位置随之变 X"
```

---

### Task 2: X 活动动画（鲸尾 → X 矢量动画）

`WhaleTail` widget 的公开 API 不变，内部从读精灵图改为矢量 X 旋转动画。

**Files:**
- Modify: `lib/ui/chat/widgets/whale_tail.dart`（重写内部，保留 `WhaleTail`/`WhaleTailState` 公开 API、`deepSeekBlue`/`deepSeekBlueDark`/`whaleColorFor`）
- Test: `test/chat/activity_strip_golden_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `WhaleTail({level, color, height, still})`：API 不变
  - `WhaleTailState.shownForm`/`rate`/`frame`：可删（原是精灵图状态），或改为 X 的旋转角度
  - `whaleColorFor(Brightness)`：保留

- [ ] **Step 1: 写失败测试**

`test/chat/activity_strip_golden_test.dart` 改为：pump 一个 `WhaleTail(level: 3, color: deepSeekBlue, height: 20)`，断言它的尺寸是 `Size(20 * aspect, 20)`（aspect ≈ 0.91），且是一个 `CustomPaint`（不再是精灵图 `SizedBox.fromSize` + 精灵图 painter）。golden 留到 Task 7。

- [ ] **Step 2: 运行测试确认失败**

`flutter test test/chat/activity_strip_golden_test.dart --name "X activity"`
预期：FAIL

- [ ] **Step 3: 重写 `whale_tail.dart`**

`WhaleTailState` 用 `Ticker` 驱动一个旋转角度，`level` 决定旋转速度（0–4 档对应 0.3×–1× 的速率，沿用原 `rateOf` 的档位语义）。`still` 时（空状态）画静止的 X。用 `Path` 画 X，随角度旋转。删掉 `WhaleSprites`/`WhaleAtlas`/`WhaleSheet`（不再读文件）。`deepSeekBlue`/`deepSeekBlueDark`/`whaleColorFor` 保留。

- [ ] **Step 4: 运行测试确认通过**

`flutter test test/chat/activity_strip_golden_test.dart --name "X activity"`
预期：PASS

- [ ] **Step 5: 提交**

```bash
git add lib/ui/chat/widgets/whale_tail.dart test/chat/activity_strip_golden_test.dart
git commit -m "鲸尾活动指示器改为 X 矢量动画，不再读精灵图"
```

---

### Task 3: 删除内置宠物（保留导入框架）

`builtInPets` 清空，默认改"不显示"，清掉硬编码的 `'whale-girl'`。框架保留。

**Files:**
- Modify: `lib/pets/pet_prefs.dart:13-17`（`builtInPets`、`defaultPetId`、`adoptDefault`、`_load` 回落）
- Modify: `lib/ui/pets/pet_picker.dart:31-32,183`（去掉内置选项）
- Modify: `lib/ui/companion/companion_chrome.dart:783-800`（`CompanionPixelWhale` 不再加载内置包）
- Modify: `lib/dev/pet_actions_probe_main.dart:38,42`（dev 调试入口改用 `noPetId` 或 mock id）
- Test: `test/access/access_pet_default_test.dart`、`test/pets/pet_import_test.dart`

**Interfaces:**
- Consumes: `noPetId`（`lib/pets/pet_state.dart:291`，`'none'`）
- Produces:
  - `builtInPets = const []`
  - `defaultPetId` 的语义：见 Step 3
  - `CompanionPixelWhale`：pack 为 null 时画一个占位（不再加载 `'whale-girl'`）

- [ ] **Step 1: 写失败测试**

`test/access/access_pet_default_test.dart` 改为：新装且 `petEnabled` 默认时，`packId == noPetId`；`petEnabled` 切换后回落逻辑正确。`test/pets/pet_import_test.dart` 里断言 `defaultPetId` 的地方改为断言 `noPetId`（删除内置包后，导入/删除后的默认回落是"不显示"）。

- [ ] **Step 2: 运行测试确认失败**

`flutter test test/access/access_pet_default_test.dart`
预期：FAIL

- [ ] **Step 3: 改 `pet_prefs.dart`**

`builtInPets = const []`，`defaultPetId = noPetId`。`adoptDefault()` 改为：`builtInPets.isEmpty` 时直接 return（不写任何偏好，初始状态保持 `packExplicit=false`），否则照旧 `setPack(defaultPetId)`。这样新装未选择时 `petEnabled` 切换仍能走 `_load` 的回落路径。老用户存过 `'deepy-whale'` 的：`_load` 里 `explicit` 判定（`pack == noPetId || builtInPets.contains(pack) || isUserPet(pack)`）全不成立，回落到 `noPetId`，不崩也不加载已删资产。加一条断言（Review Focus 第 2 条）：新装、`petEnabled=true`、未做任何选择时，`petPrefsProvider` 的 `packExplicit == false` 且 `packId == noPetId`。

- [ ] **Step 4: 改 `pet_picker.dart`**

`_source` 里 `'deepy-whale'`/`'whale-girl'` 的 l10n 映射删掉。内置选项循环 `for (final id in builtInPets)` 自然不显示（列表为空），可加注释说明内置已移除。

- [ ] **Step 5: 改 `companion_chrome.dart` 的 `CompanionPixelWhale`**

不再 `petPackProvider('whale-girl')`。改为画一个占位（`SizedBox` 或简单的 X 形），`pack` 逻辑整个删掉。注释更新。加一条断言（Review Focus 第 5 条）：`CompanionPixelWhale` 的 widget 树里不出现 `petPackProvider` 的任何调用（`ref.watch` 找不到），即不触发资产加载。

- [ ] **Step 6: 改 `pet_actions_probe_main.dart`**

`'whale-girl'` 改成 `noPetId` 或一个 `user-` 前缀的 mock id。

- [ ] **Step 7: 运行测试确认通过**

`flutter test test/access/access_pet_default_test.dart test/pets/pet_import_test.dart`
预期：PASS

- [ ] **Step 8: 提交**

```bash
git add lib/pets/pet_prefs.dart lib/ui/pets/pet_picker.dart lib/ui/companion/companion_chrome.dart lib/dev/pet_actions_probe_main.dart test/access/access_pet_default_test.dart test/pets/pet_import_test.dart
git commit -m "删除内置宠物包，默认不显示，保留用户导入框架"
```

---

### Task 4: 求 Star 贴纸 → X 徽章

删 `StarPicture` 的 `Image.asset`，换成矢量 X 徽章；删 `precacheImage`。

**Files:**
- Modify: `lib/ui/star/star_prompt_dialog.dart`（`StarPicture` 改为画 X 徽章，删 `asset` 常量或保留指向不存在的文件）
- Modify: `lib/ui/star/star_prompt_host.dart:75`（删 `precacheImage`）
- Test: `test/star/star_prompt_test.dart`

**Interfaces:**
- Consumes: `StarPromptDialog.pictureMin`/`pictureMax`（保留，X 徽章沿用同一尺寸逻辑）
- Produces:
  - `StarPicture(side:)`：改画矢量 X 徽章（圆形光晕 + X），不再读 `assets/star/star_whale.webp`

- [ ] **Step 1: 写失败测试**

`test/star/star_prompt_test.dart:267` 的 `precacheImage` 断言删掉（不再预缓存）。`:748-753` 的 picture rect 断言保留，但 `StarPicture` 现在是 X 徽章，尺寸逻辑不变（`pictureMin`/`pictureMax` 之间的方形）。加一条断言（Review Focus 第 3 条）：pump 弹窗后 `find.byType(Image)`  findsNothing（不再有 `Image.asset`，坏图占位符不会出现）。

- [ ] **Step 2: 运行测试确认失败**

`flutter test test/star/star_prompt_test.dart`
预期：FAIL（precache 断言还在，或 X 徽章还没实现）

- [ ] **Step 3: 改 `star_prompt_dialog.dart`**

`StarPicture` 里的 `Image.asset(StarPromptDialog.asset)` 换成画 X 的 `CustomPaint`（或一个圆形光晕 + X 矢量）。`asset` 常量可以删掉，或留着指向 `assets/star/star_whale.webp`（文件已删，不会再被读）。

- [ ] **Step 4: 改 `star_prompt_host.dart`**

删掉 `unawaited(precacheImage(const AssetImage(StarPromptDialog.asset), context));`（line 75）。

- [ ] **Step 5: 运行测试确认通过**

`flutter test test/star/star_prompt_test.dart`
预期：PASS（golden 留到 Task 7）

- [ ] **Step 6: 提交**

```bash
git add lib/ui/star/star_prompt_dialog.dart lib/ui/star/star_prompt_host.dart test/star/star_prompt_test.dart
git commit -m "求 Star 弹窗的鲸鱼贴纸换成 X 徽章，删预缓存"
```

---

### Task 5: 删除资产文件 + pubspec 声明

删四个素材目录，同步删 pubspec.yaml 里对应的 asset 声明。

**Files:**
- Delete: `assets/brand/`、`assets/pets/deepy-whale/`、`assets/pets/whale-girl/`、`assets/star/`、`assets/whale/`
- Modify: `pubspec.yaml:145,155-156,158`（删 `- assets/whale/`、`- assets/pets/deepy-whale/`、`- assets/pets/whale-girl/`、`- assets/star/`）
- Modify: `tool/make_whale_sprites.py`（文件头标注废弃：鲸尾已改矢量，此脚本不再被使用）

**Interfaces:**
- Consumes: Task 1–4 已经让代码不再读这些文件
- Produces: 构建不再依赖这四个目录

- [ ] **Step 1: 删除目录**

```bash
rm -rf assets/brand assets/pets/deepy-whale assets/pets/whale-girl assets/star assets/whale
```

注意：`assets/pets/` 整个目录删空后如果没有任何子目录，`rm -rf assets/pets` 也可以（用户导入的宠物是运行时数据，在 `<app support>/pets/`，不在 `assets/`）。

- [ ] **Step 2: 删 pubspec 声明**

从 `pubspec.yaml` 的 `assets:` 列表删掉 `- assets/whale/`、`- assets/pets/deepy-whale/`、`- assets/pets/whale-girl/`、`- assets/star/`。`assets/brand/` 没在 pubspec 声明，无需动。

- [ ] **Step 3: 标注 make_whale_sprites.py 废弃**

文件头加注释：`DEPRECATED — 鲸尾已改为矢量 X 动画（whale_tail.dart），此脚本不再被使用，保留供参考。`

- [ ] **Step 4: 验证构建**

`flutter pub get && flutter analyze`
预期：零 error（warning 可接受，但不应有 "asset not found" 或 "declared asset missing"）

- [ ] **Step 5: 提交**

```bash
git add -A assets/ pubspec.yaml tool/make_whale_sprites.py
git commit -m "删除版权素材目录和 pubspec 声明"
```

---

### Task 6: 修复受影响的测试

删除内置宠物资产和鲸尾精灵图后，直接引用它们的测试会挂。逐个修复。

**Files:**
- Modify: `test/pets/pet_pack_test.dart`（读 `assets/pets/<id>/pack.json` 的内置包格式测试）
- Modify: `test/pets/pet_pixel_test.dart`（加载内置精灵图的像素测试）
- Modify: `test/pets/pet_mood_test.dart:582,587`（`packId: 'deepy-whale'`）
- Modify: `test/pets/overlay/overlay_channel_test.dart:34,44`（`packId: 'deepy-whale'`）
- Modify: `test/pets/pet_parts_test.dart:302`（`packId: 'whale-girl'`）
- Modify: `test/pets/support.dart:35-36`（`diskPack('deepy-whale')`/`diskPack('whale-girl')`）
- Modify: `test/pets/pet_library_test.dart:109,145,258`（引用内置 id）
- Modify: `test/chat/activity_strip_golden_test.dart`、`test/star/star_prompt_test.dart`（golden 相关，留 Task 7）

**Interfaces:**
- Consumes: `noPetId`、`builtInPets = []`、`defaultPetId = noPetId`
- Produces: 全量 `flutter test` 在 Task 7 重新生成 golden 前只剩 golden 不匹配

- [ ] **Step 1: 跑一遍测试，列出失败**

`flutter test test/pets/ test/access/ test/chat/activity_strip_golden_test.dart test/star/ 2>&1 | tail -40`
预期：一批 FAIL（读已删的资产文件、断言已改的默认值）

- [ ] **Step 2: 修 `pet_pack_test.dart`**

这个测试验证内置包的格式和测量值。内置包删了，测试没有对象可测。整组 `group('Deepy 小鲸鱼')` 和 `group('鲸娘')` 删掉，或改为验证一个用户导入的 mock 包。推荐删掉（内置包已不存在，格式测试失去意义）。

- [ ] **Step 3: 修 `pet_pixel_test.dart`**

同样读内置精灵图。删掉或改为 mock 包。推荐删掉。

- [ ] **Step 4: 修 `support.dart`**

`diskPack('deepy-whale')`/`diskPack('whale-girl')` 读已删的文件。改成构造一个内存里的 mock `PetPack`（不读文件），供其它测试引用。`deepy`/`girl` 改成 mock 对象。

- [ ] **Step 5: 修 `pet_mood_test.dart`、`overlay_channel_test.dart`、`pet_parts_test.dart`**

`packId: 'deepy-whale'`/`'whale-girl'` 改成 `noPetId` 或 mock id。

- [ ] **Step 6: 修 `pet_library_test.dart`**

`isUserPet('deepy-whale')` 等断言内置 id 不是用户宠物的地方，改成用任意非 `user-` 前缀的 id。`for (final id in ['deepy-whale', 'whale-girl'])` 的循环删掉（内置没了）。

- [ ] **Step 7: 运行测试确认通过**

`flutter test test/pets/ test/access/`
预期：PASS（activity_strip 和 star_prompt 的 golden 仍会挂，留 Task 7）

- [ ] **Step 8: 提交**

```bash
git add test/pets/ test/access/
git commit -m "修复因删除内置宠物资产而挂的测试"
```

---

### Task 7: 重新生成受影响的 golden

品牌标、活动指示器、求 Star 弹窗的 golden 截图要重拍。

**Files:**
- Regenerate: `test/shell/goldens/brand_mark_light.png`、`test/shell/goldens/brand_mark_dark.png`
- Regenerate: `test/star/goldens/star_prompt_light.png`、`test/star/goldens/star_prompt_dark.png`
- Regenerate: `test/chat/goldens/`（activity_strip 相关）
- Regenerate: `test/update/goldens/update_sheet_star_*.png`（更新弹窗里的 BrandMark）

**Interfaces:**
- Consumes: Task 1–4 的 X 形象
- Produces: 与 X 形象一致的 golden

- [ ] **Step 1: 重拍 golden**

```bash
flutter test --update-goldens test/shell/brand_mark_test.dart test/star/star_prompt_test.dart test/chat/activity_strip_golden_test.dart test/update/
```

- [ ] **Step 2: 检查 golden 内容**

打开生成的 PNG，确认画的是 X 而不是鱼尾/鲸尾，没有坏图占位符。

- [ ] **Step 3: 运行测试确认通过**

`flutter test test/shell/brand_mark_test.dart test/star/star_prompt_test.dart test/chat/activity_strip_golden_test.dart test/update/`
预期：PASS

- [ ] **Step 4: 提交**

```bash
git add test/shell/goldens/ test/star/goldens/ test/chat/goldens/ test/update/goldens/
git commit -m "重拍品牌标、活动指示器、求 Star 弹窗的 golden"
```

---

### Task 8: 改名 Xagent（包名 + Info.plist + AppInfo）

**Files:**
- Modify: `pubspec.yaml:2-3`（`name: dsh_app` → `name: xagent`，`description` 改）
- Modify: 全部 ~1044 个 `import 'package:dsh_app/...'` → `import 'package:xagent/...'`
- Modify: `app/ios/Runner/Info.plist`（`CFBundleName` 从 `dsh_app` 改 `Xagent`）
- Modify: `lib/state/app_info.dart:19,23`（`name`/`wordmark` 从 `'AgentPort'` 改 `'Xagent'`）

**Interfaces:**
- Consumes: Task 1–7 已全部完成，代码可编译
- Produces: 包名 `xagent`，App 内显示名 `Xagent`

- [ ] **Step 1: 改 pubspec 包名**

`pubspec.yaml` 的 `name: dsh_app` 改 `name: xagent`，`description` 从 `"DSH — DeepSeek Harness on your phone"` 改 `"Xagent — 远程 Agent 客户端"`。

- [ ] **Step 2: 批量改 import**

```bash
grep -rl "package:dsh_app/" lib test | xargs sed -i '' 's|package:dsh_app/|package:xagent/|g'
```

- [ ] **Step 3: 改 Info.plist**

`CFBundleName` 从 `dsh_app` 改 `Xagent`。`CFBundleDisplayName` 已经是 `Xagent`（未提交改动），保留。

- [ ] **Step 4: 改 `app_info.dart`**

`name` 和 `wordmark` 从 `'AgentPort'` 改 `'Xagent'`。

- [ ] **Step 5: 运行 analyze 确认零 error**

`flutter pub get && flutter analyze`
预期：零 error（sed 可能漏掉某些写法，analyze 会抓出来）

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "包名 dsh_app 改 xagent，App 显示名 Xagent"
```

---

### Task 9: 全量验证

**Files:** 无（验证任务）

**Interfaces:**
- Consumes: 全部前面的任务
- Produces: `flutter analyze` 零 error + `flutter test` 全绿

- [ ] **Step 1: 全量 analyze**

`flutter analyze`
预期：零 error（warning/info 记录但不阻塞）

- [ ] **Step 2: 全量测试**

`flutter test`
预期：全绿

- [ ] **Step 3: iOS 构建**

```bash
flutter build ios --no-codesign
```
预期：构建成功，产物里没有 dsh-go 的素材残留（`assets/brand/`、`assets/pets/`、`assets/star/`、`assets/whale/` 都在包里找不到）

- [ ] **Step 4: 检查残留引用**

```bash
grep -rn "deepy-whale\|whale-girl\|assets/brand\|assets/whale\|assets/star" lib --include="*.dart" | grep -v "test/"
grep -rn "AgentPort\|dsh_app" lib --include="*.dart" | head
```
预期：无（除了 test 里的 mock id 和文档注释）

- [ ] **Step 5: 提交（如有收尾改动）**

```bash
git add -A
git commit -m "品牌清理与改名完成"
```

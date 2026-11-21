# 第三方声明（Third-Party Notices）

本文件集中列出 dsh-go（dsh-Go-ios）复制或改写进源码的第三方代码与素材，以及随 App 一起分发的字体和原生库。源文件头用 `SPDX-FileCopyrightText` / `SPDX-License-Identifier` 或 `Portions derived from …` 标记版权与许可，并指向本文件；各项目的派生关系见各条目。

- App 内「设置 › 开源许可」页随 App 分发同样的声明（`app/lib/ui/common/third_party_licenses.dart`，字体在 `app/lib/ui/settings/font_licenses.dart`）。
- Dart / Flutter 依赖应按 `app/pubspec.lock`（以及本地包的 lock）核对直接与传递依赖；Flutter 从包根 `LICENSE` 收集许可并显示在许可证页。这里不逐包重复，发行前仍须核验实际发行物的许可资产。
- 本项目自己的许可见 `LICENSE`（AGPL-3.0）；品牌标识和吉祥物美术不属于第三方，也不在 AGPL 授权范围内。
- 本项目是 [dsh-go](https://github.com/ccch1mneyyy/dsh-go)（AGPL-3.0，原作者 ccch1mneyyy）的 iOS 二开版本。上游的 Android-only 库（Google ML Kit、Shizuku-API、libadb-android、spake2-android、Conscrypt、Bouncy Castle、XZ for Java、AndroidX WebKit、AudioSwitch）随 `app/android/` 一并不在本 iOS fork 的分发范围内，本文件不列它们。

## 一、复制或改写进源码的代码

### PiPilot（MIT）

| 项 | 内容 |
|---|---|
| 项目 | PiPilot，https://github.com/CikeSeven/pi_pilot |
| 版权人 | Copyright (c) 2026 CikeSeven |
| 许可 | MIT |
| 用途 | 聊天界面、通用组件、抽屉外壳与主题的结构和部分实现 |

均在 `app/lib/ui/` 下：`chat/`、`chat/render/`、`chat/widgets/`、`common/`、`settings/`、`shell/`、`theme/` 下的派生文件（源文件头注明出处）。

### DeepSeek Harness（MIT）

| 项 | 内容 |
|---|---|
| 项目 | DeepSeek Harness，https://github.com/deepseek-ai/deepseek-harness |
| 版权人 | Copyright (c) 2026 DeepSeek |
| 许可 | MIT |
| 用途 | 移植官方客户端的若干算法与图形；部分组件的结构与行为参照其 Web 客户端 |

派生文件：`app/lib/ui/chat/secret_mask.dart`、`app/lib/ui/chat/widgets/artifact_card.dart`、`app/lib/state/session_search.dart`、`app/lib/ui/features/schedule_editor/cron.dart`、`app/lib/ui/engine_settings/namespace_copy.dart`、`app/lib/ui/common/think_glyph.dart`、`packages/dsh_client/lib/src/binary_response.dart`、`packages/dsh_client/lib/src/deliverables.dart`（源文件头注明上游来源）。

### Phase（MIT，作者授权）

| 项 | 内容 |
|---|---|
| 项目 | Phase，https://github.com/CikeSeven/phase （基于提交 `c209f6f`） |
| 版权人 | Copyright (c) 2026 CikeSeven |
| 许可 | MIT：作者授权本项目按 MIT 许可使用 |
| 用途 | 手机操控（无障碍读屏与操作、控制浮层、不打扰特权虚拟屏）。iOS fork 不编译这些 Kotlin 派生代码，但许可声明保留 |

声明原文：

```text
Portions of the phone control feature are derived from Phase
(https://github.com/CikeSeven/phase), Copyright (c) 2026 CikeSeven,
used under the MIT License with the author's permission.
```

### DS Bot（Apache-2.0，已修改）

| 项 | 内容 |
|---|---|
| 项目 | DS Bot，https://github.com/Fei2411/DeepSeek-Bot （基于提交 `1bebe82`） |
| 版权人 | Copyright 2026 Fei2411 and the DS Bot contributors |
| 许可 | Apache License 2.0 |
| 用途 | 可交互回复（dsh-ui）的规范化、校验、上限、摘要、选择规则与图表刻度；DS Bot 客户端的配色与默认颜色 |

派生文件：`app/lib/ui/chat/dsh_ui/`（`dsh_ui_model.dart`、`dsh_ui_reply.dart`、`dsh_ui_chart.dart`）、`app/test/chat/dsh_ui/dsh_ui_model_test.dart`、`packages/dsh_client/lib/src/dsbot_api.dart`、`app/lib/ui/bots/bot_mention.dart`（源文件头注明上游来源与改动说明）。DS Bot 的 NOTICE 原文见上游 dsh-go 的 THIRD_PARTY_NOTICES.md。

### ds-harness-remote（MIT）

| 项 | 内容 |
|---|---|
| 项目 | ds-harness-remote，https://github.com/liguobao/ds-harness-remote |
| 版权人 | Copyright (c) 2026 DSH Remote contributors |
| 许可 | MIT（全文另见 `packages/dsh_remote/LICENSE-ds-harness-remote`） |
| 用途 | 远程连接：协议、分帧、校验、加密信道、直连（WebRTC）与连接逻辑 |
| 对应上游版本 | `7e387df`（Host 插件 0.6.0）；工作区上传协议参考 `479b94341c0d0de63846f21d0fcca26997d158d1`（Host 插件 0.6.2） |

路径均相对 `packages/dsh_remote/`：`lib/src/server/`、`lib/src/account/`、`lib/src/carrier/`、`lib/src/crypto/`、`lib/src/channel/`、`lib/src/protocol/`、`lib/src/transport/`、`lib/src/util/`、`test/fixtures/`、`tool/e2e/`（源文件头注明上游来源）。

### DSHA（MIT）

| 项 | 内容 |
|---|---|
| 项目 | DSHA，https://github.com/DSH-APP/DSHA |
| 版权人 | Copyright (c) 2026 qiannianhuanxiang |
| 许可 | MIT |
| 用途 | 不打扰模式特权进程的 `app_process` 入口（iOS fork 不编译此代码，但许可声明保留） |

## 二、素材

### Phosphor Icons（MIT）

| 项 | 内容 |
|---|---|
| 项目 | Phosphor Icons 2.1.1，https://phosphoricons.com （`@phosphor-icons/core`） |
| 版权人 | Copyright (c) 2023 Phosphor Icons |
| 许可 | MIT |
| 用途 | 界面图标字体的字形；少数图标按它的网格与轮廓补画 |

- `app/tool/icons/phosphor/`：图标源文件与 LICENSE
- `app/assets/fonts/DshIcons.ttf`、`app/lib/ui/theme/dsh_glyphs.dart`：由 `app/tool/make_icon_font.py` 生成

### Material Icons（Apache-2.0）

| 项 | 内容 |
|---|---|
| 项目 | Material Icons，https://github.com/google/material-design-icons |
| 版权人 | Google |
| 许可 | Apache License 2.0 |
| 用途 | App 内图标字体的字形；随 App 分发 |

### discourse-emojis（MIT）

| 项 | 内容 |
|---|---|
| 项目 | discourse-emojis，https://github.com/discourse/discourse-emojis |
| 版权人 | Discourse（gemspec 作者 Joffrey Jaffeux） |
| 许可 | MIT（见其 `discourse-emojis.gemspec`） |
| 用途 | 论坛表情的名称与别名表，只用数据，不含图片 |
| 文件 | `app/lib/forum/emoji_data.g.dart`，由上游 `infra/forum/tools/gen_emoji_table.py` 从 `dist/emojis.json`、`dist/aliases.json` 生成 |

### JetBrains Mono（SIL OFL 1.1）

| 项 | 内容 |
|---|---|
| 项目 | JetBrains Mono，https://github.com/JetBrains/JetBrainsMono |
| 版权人 | Copyright 2020 The JetBrains Mono Project Authors |
| 许可 | SIL Open Font License 1.1，全文见 `app/assets/fonts/OFL.txt` |
| 用途 | 代码字体，随 App 分发 |

## 三、随 App 分发的原生库

### flutter_webrtc（MIT + Apache-2.0）

| 项 | 内容 |
|---|---|
| 项目 | flutter_webrtc，https://github.com/9200-9998/flutter-webrtc |
| 版权人 | Copyright (c) 2018 湖北捷智云技术有限公司（flutter_webrtc）；Copyright (c) 2015 Howard Yang（react-native-webrtc） |
| 许可 | MIT（pub 包自带）；其 NOTICE 另含 react-native-webrtc（MIT）与 Shiguredo 的 simulcast 编码器包装（Apache-2.0） |
| 用途 | DSH Remote 直连（P2P / TURN）的 DataChannel |

### WebRTC（BSD-3-Clause + Google 专利授权）

| 项 | 内容 |
|---|---|
| 项目 | WebRTC，https://webrtc.org |
| 版本 | 150.7871.04（libwebrtc m150） |
| 版权人 | Copyright (c) 2011, The WebRTC project authors |
| 许可 | BSD-3-Clause，另附 Google 的专利授权（PATENTS） |
| 用途 | flutter_webrtc 的原生 WebRTC 库 |

完整上游通知的随包收录见 `app/assets/licenses/webrtc-150.7871.04.md`（随 App 打包，设置开源许可页的 `WebRTC` 条目展示全部章节）。

## 四、字体与数据

### Unicode Character Database 15.0.0（Unicode 数据许可）

宠物 ZIP 文件名去重使用从 CPython 3.12 / Unicode 15.0.0 生成的 NFC 与 full casefold 数据表；生成脚本为 `app/tool/generate_pet_validation_data.py`，表为 `app/lib/pets/pet_unicode_data.g.dart`。未复制 CPython 实现代码。

Copyright © 1991-2026 Unicode, Inc.

许可全文原样存于 `app/tool/unicode-15.0-LICENSE.txt`，同字节打包为 `app/assets/licenses/unicode-15.0.txt`。

## 许可证全文

### MIT License

适用于以下版权声明：

```text
Copyright (c) 2026 CikeSeven                                   (PiPilot)
Copyright (c) 2026 CikeSeven                                   (Phase)
Copyright (c) 2026 DeepSeek                                    (DeepSeek Harness)
Copyright (c) 2026 DSH Remote contributors                     (ds-harness-remote)
Copyright (c) 2026 qiannianhuanxiang                           (DSHA)
Copyright (c) 2023 Phosphor Icons                              (Phosphor Icons)
Copyright (c) 2018 湖北捷智云技术有限公司                        (flutter_webrtc)
Copyright (c) 2015 Howard Yang                                 (react-native-webrtc)
```

discourse-emojis 上游未附 LICENSE 文件与版权行，按其 gemspec 声明的 MIT 使用。

```text
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache License 2.0

适用于 DS Bot、Material Icons、flutter_webrtc 的 Apache-2.0 部分。

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.
```

完整 Apache License 2.0 全文见上游 dsh-go 的 THIRD_PARTY_NOTICES.md（https://github.com/ccch1mneyyy/dsh-go/blob/master/THIRD_PARTY_NOTICES.md）。

### NOTICE：DS Bot（提交 `1bebe82`，原文照录）

```text
DS Bot
Copyright 2026 Fei2411 and the DS Bot contributors

This product is licensed under the Apache License, Version 2.0 (see LICENSE).
```

### WebRTC BSD 与 Google 专利授权

```text
Copyright (c) 2011, The WebRTC project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Additional IP Rights Grant (Patents)

"This implementation" means the copyrightable works distributed by
Google as part of the WebRTC code package.

Google hereby grants to you a perpetual, worldwide, non-exclusive,
no-charge, irrevocable (except as stated in this section) patent
license to make, have made, use, offer to sell, sell, import,
transfer, and otherwise run, modify and propagate the contents of this
implementation of the WebRTC code package, where such license applies
only to those patent claims, both currently owned by Google and
acquired in the future, licensable by Google that are necessarily
infringed by this implementation of the WebRTC code package. This
grant does not include claims that would be infringed only as a
consequence of further modification of this implementation. If you or
your agent or exclusive licensee institute or order or agree to the
institution of patent litigation against any entity (including a
cross-claim or counterclaim in a lawsuit) alleging that this
implementation of the WebRTC code package or any code incorporated
within this implementation of the WebRTC code package constitutes
direct or contributory patent infringement, or inducement of patent
infringement, then any patent rights granted to you under this License
for this implementation of the WebRTC code package shall terminate as
of the date such litigation is filed.
```

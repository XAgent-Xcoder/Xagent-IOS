# Xagent 品牌标识交付 · v1.0

先看 00_Guide/brand-guidelines.pdf。identity-preview.png 可用于快速预览，selected-concept.png 为所选概念的原始局部。正式资产由该图重绘，前后折面采用纯色，字标转曲。

| 目录 | 用法 |
|---|---|
| 01_Vector | 设计母版。在 Figma 或 Illustrator 中导入 SVG。mark 为独立 X，wordmark 为字标，lockup-stacked 为原稿竖组合，lockup-horizontal 为横组合，lockup-one-color 为单色横组合。light/dark 表示放置背景，reverse 表示白色。full-bleed 为系统图标，rounded-preview 用于排版。 |
| 02_PNG | 按资产、版本、实际像素宽度拆分。字标、图形和组合周围均为透明；反白文件应放在深色背景上看。文件名中的 w 代表像素宽度。 |
| 03_iOS | AppIcon.appiconset 对应当前 iOS 项目的 Contents.json 文件名与槽位。含 iPhone、iPad 与 1024 营销图。方形不透明底图，系统负责裁圆角。 |
| 04_Android | res 可合入 Android 模块资源。清单图标引用 @mipmap/ic_launcher；若已有 roundIcon，亦可引用同一资源。普通密度适配 PNG、v26 自适应图标与 v33 单色图层独立提供。Play 商店图单独存放。 |
| 05_Web | 将目录内容部署至 /brand/，将 head-snippet.html 中的标签合入网页 head；如路径变化，同步调整 href。已有 PWA 配置的站点应合并 icons 与色值。 |
| 06_Print | 通用矢量 PDF、EPS；彩色文件使用 RGB。lockup-horizontal-K100.pdf 为单黑版，面向单色输出。彩印需按实际印刷条件转换并打样。 |
| 07_Tokens | JSON 供跨端读取，CSS 变量供网页使用。presentation-paper 只作展示背景。 |
| 08_Motion | 每个折面单独一层 SVG，四个文件共用画板和坐标；叠放顺序见 layer-order.txt。 |

横组合、单色、反白及留白和尺寸规则为本次交付延展。所有文件均独立交付，应用工程接入时选取对应目录。

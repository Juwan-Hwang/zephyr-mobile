# tokens

- 桌面来源：`vendor/zephyr/packages/tokens/src/*.json`（子模块，只读，不改）。
- 移动增补：`mobile.json`（只放手机特有值；与桌面同名会直接报错）。
- 生成：`node tokens/build.mjs`（零依赖）→ `generated/ios/ZTokens.swift`、`generated/android/ZTokens.kt`、`generated/harmony/ZTokens.ets` + `generated/harmony/resources/{base,dark}/element/color.json`。CI 用 `--check` 校验产物最新。**禁止手改产物。**

## 引用方式
- iOS（XcodeGen）：把 `../../tokens/generated/ios` 加进设计系统 target 的 `sources`。用法：`ZTokens.Colors.textPrimary`（动态色）、`.zType(ZTokens.TypeStyle.metric)`（随 Dynamic Type 缩放）、`ZTokens.LatencyThreshold.color(ms)`。
- Android（Gradle `:design`）：`kotlin.sourceSets["main"].kotlin.srcDir("$rootDir/../../tokens/generated/android")`（按 apps/android 实际层级调整）。用法：`CompositionLocalProvider(LocalZColors provides if (dark) ZColors.Dark else ZColors.Light)`，组件内 `LocalZColors.current.textPrimary`、`ZType.metric`、`ZLatency.color(ms, colors)`。包名 `com.zephyr.design.tokens`。
- 鸿蒙（ArkTS，D）：构建前把 `tokens/generated/harmony/resources/*/element/color.json` 合并进模块的 `resources/{base,dark}/element/`（或由 hvigor 脚本拷贝），组件用 `$r('app.color.text_primary')` 自动跟随深浅色；常量从 `ZTokens.ets` 导入：`ZSpace.md`、`ZType.metric`、`curves.cubicBezierCurve(...ZEasing.standard)`、`ZLatency.color(ms, zColors(isDark))`。颜色值为 `#AARRGGBB`，尺寸 vp、字号 fp、时间 ms。
- 鸿蒙术语（i18n）：`node tools/gen-harmony-i18n.mjs` 由 `contract/i18n/glossary-v1.json` 生成 `generated/harmony/resources/{base,zh,ja,…}/element/string.json`（名称 `term_<key>`，`.` 换成 `_`；base 为英文）和 `generated/harmony/ZTerms.ets`（`ZTerm.nodes`、`ZTerm.modeRule` …）。与 color.json 一样合并进模块 resources；CI 用 `--check` 校验。界面其余文案由鸿蒙端自管，术语一律用 `ZTerm`，保证三端同名。
- 强调色：`ZTokens.Accent` / `ZAccent`（blue 默认，green / orange / pink）。紫色已废弃。

## 对比度检查（WCAG AA）
`node tools/check-token-contrast.mjs [--verbose|--json]`，CI 在 contract 作业跑（零依赖，读的是 token 源，与 `build.mjs` 同一套合并 / 引用规则）。

- 浅色、深色各算一遍。半透明前景（`screen.t3`、`latency.unknown` 等）先按 alpha 合成到背景上再算；半透明背景 `screen.glass` 合成到每个可能的底（`bg` / `s1`–`s4`）上，取最差值。与 `build.mjs` 一样拒绝 mobile.json 与桌面顶层同名。
- 阈值：**正文 4.5**（字号 < 18pt 常规 / < 14pt 粗体）；**UI 3.0**（大字、图标、控件状态，WCAG 1.4.3 大字 / 1.4.11 非文本）。
- 检查的组合（完整列表见脚本 `PAIRS`）：

| 前景 | 背景 | 阈值 |
|---|---|---|
| `screen.t1` / `t2` / `t3` | `screen.bg`、`s1`、`s2`、`s3`、`s4`、`glass` | 4.5 |
| `screen.on-primary` | `screen.primary` | 4.5 |
| `latency.normal` / `unknown` / `slow` / `timeout` | `screen.s1`、`s2`、`bg` | 4.5 |
| `screen.amber` / `red` / `green`（作文字） | `screen.s1`、`s2`、`bg` | 4.5 |
| `color.download`、`screen.up`（速率箭头） | `screen.s1`、`s2`、`bg` | 3.0 |
| 强调色 blue / green / orange / pink | `screen.bg`、`s1` | 3.0（默认 blue 作小字另在 `bg`、`s1`、`s4` 上按 4.5） |
| `text.on-accent`（按钮 15pt、胶囊 14pt） | 各强调色 | 4.5 |
| Android 深色强调色 `ZAccent.darkVariant()`（读 `apps/android/.../ZColors.kt`，存在才查） | `screen.bg`、`s1`；白字在其上 | 3.0 / 4.5 |
| `screen.t4` | `screen.bg`、`s1` | 3.0 |

- 不达标的组合必须进脚本里的 `ALLOW`，并写 `reason`：`intentional` 是有意为之且确认无可读用途，`debt` 是已知欠账。目前 41 条全部是 debt：浅色 amber / green / red 作文字、强调色小字与强调色底白字、t4 仍被用于序号 / 未测延迟 / chevron、浅色 t3 在 s4 上。修复要加浅色文字专用色或调整用法，并重录两端快照基线。已达标的 ALLOW 条目会报 STALE，修好后记得删。
- 历史：浅色 `screen.t3` / `latency.unknown` 0.4→0.55、深色 `t3` 0.4→0.5，都是为了过这道线；改这些值之前先跑一遍脚本。

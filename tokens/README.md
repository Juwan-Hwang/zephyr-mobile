# tokens

- 桌面来源：`vendor/zephyr/packages/tokens/src/*.json`（子模块，只读，不改）。
- 移动增补：`mobile.json`（只放手机特有值；与桌面同名会直接报错）。
- 生成：`node tokens/build.mjs`（零依赖）→ `generated/ios/ZTokens.swift`、`generated/android/ZTokens.kt`、`generated/harmony/ZTokens.ets` + `generated/harmony/resources/{base,dark}/element/color.json`。CI 用 `--check` 校验产物最新。**禁止手改产物。**

## 引用方式
- iOS（XcodeGen）：把 `../../tokens/generated/ios` 加进设计系统 target 的 `sources`。用法：`ZTokens.Colors.textPrimary`（动态色）、`.zType(ZTokens.TypeStyle.metric)`（随 Dynamic Type 缩放）、`ZTokens.LatencyThreshold.color(ms)`。
- Android（Gradle `:design`）：`kotlin.sourceSets["main"].kotlin.srcDir("$rootDir/../../tokens/generated/android")`（按 apps/android 实际层级调整）。用法：`CompositionLocalProvider(LocalZColors provides if (dark) ZColors.Dark else ZColors.Light)`，组件内 `LocalZColors.current.textPrimary`、`ZType.metric`、`ZLatency.color(ms, colors)`。包名 `com.zephyr.design.tokens`。
- 鸿蒙（ArkTS，D）：构建前把 `tokens/generated/harmony/resources/*/element/color.json` 合并进模块的 `resources/{base,dark}/element/`（或由 hvigor 脚本拷贝），组件用 `$r('app.color.text_primary')` 自动跟随深浅色；常量从 `ZTokens.ets` 导入：`ZSpace.md`、`ZType.metric`、`curves.cubicBezierCurve(...ZEasing.standard)`、`ZLatency.color(ms, zColors(isDark))`。颜色值为 `#AARRGGBB`，尺寸 vp、字号 fp、时间 ms。
- 鸿蒙术语（i18n）：`node tools/gen-harmony-i18n.mjs` 由 `contract/i18n/glossary-v1.json` 生成 `generated/harmony/resources/{base,zh,ja,…}/element/string.json`（名称 `term_<key>`，`.` 换成 `_`；base 为英文）和 `generated/harmony/ZTerms.ets`（`ZTerm.nodes`、`ZTerm.modeRule` …）。与 color.json 一样合并进模块 resources；CI 用 `--check` 校验。界面其余文案由鸿蒙端自管，术语一律用 `ZTerm`，保证三端同名。
- 强调色：`ZTokens.Accent` / `ZAccent`（blue 默认，green / orange / pink）。紫色已废弃。单一来源 `mobile.json` 的 `accent.<name>.{base,text,fill,on-fill}`（value = 深色、lightValue = 浅色）：

| 角色 | 用途 | iOS | Android | 鸿蒙 |
|---|---|---|---|---|
| base | 开关 / 进度 / 光晕 / 选中描边等填充与大图形；深色即原 Android `ZColors.kt` 的 `darkVariant()` | `Accent.adaptive` | `ZAccent.base(dark)` / `colorDark` | `$r('app.color.accent_blue')` / `zAccentColors(name, isDark).base` |
| text | 前景小字、链接、索引条、搜索高亮、「+」等图标（浅色加深，过正文 4.5） | `Accent.text` | `ZAccent.text(dark)` | `accent_<name>_text` / `.text` |
| fill + on-fill | 主按钮、选中胶囊的底与字（green / orange 为黑字） | `Accent.fill` / `.onFill` | `ZAccent.fill(dark)` / `onFill(dark)` | `accent_<name>_fill` / `_on_fill` |

  `ZTokens.Accent.color` / `ZAccent.color` 保留为历史单一值（= 浅色 base），只为不让现有基线漂移；新代码不要再用它作前景文字或按钮底。Android `ZColors.kt` 的 `darkVariant()` 应改为 `ZAccent.base(dark)`（值相同，不影响快照）。

## 状态色作文字（2026-11-21）
- 浅色下 `screen.amber` / `green` / `red`（#FF9F0A / #34C759 / #FF3B30）作文字只有 1.8–3.6:1。文字一律用 `screen.amber-text`（浅 #B25000）/ `green-text`（浅 #1F7A35）/ `red-text`（浅 #D70015），深色与原色相同。原色只给圆点、进度条、图标填充，并且必须配形状或文字（契约 §18.b）。
- `latency.slow` / `latency.timeout` 是读数文字，浅色值将改为与 `*-text` 相同（PR `agent/a/tokens-light-status`，需两端重录基线）。

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
| `screen.amber-text` / `red-text` / `green-text`（状态色作文字） | `screen.s1`、`s2`、`bg` | 4.5 |
| 旧用法：`screen.amber` / `red` / `green` 直接作文字 | `screen.s1`、`s2`、`bg` | 4.5（记 debt，平台切到 `*-text` 后删除；之后原色只作圆点 / 进度条 / 图标） |
| `color.download`、`screen.up`（速率箭头） | `screen.s1`、`s2`、`bg` | 3.0 |
| 强调色 blue / green / orange / pink | `screen.bg`、`s1` | 3.0（默认 blue 作小字另在 `bg`、`s1`、`s4` 上按 4.5） |
| `accent.*.text` | `screen.bg`、`s1`、`s4` | 4.5 |
| `accent.*.on-fill` | `accent.*.fill` | 4.5 |
| `accent.*.base` 深色 | `screen.bg`、`s1` | 3.0 |
| 旧用法：强调色单一值作前景 / 小字，`text.on-accent` 在单一值或深色 base 上 | — | 3.0 / 4.5（记 debt，平台切换后删除） |
| `screen.t4` | `screen.bg`、`s1` | 3.0 |

- 不达标的组合必须进脚本里的 `ALLOW`，并写 `reason`：`intentional` 是有意为之且确认无可读用途，`debt` 是已知欠账；reason 以「旧用法」开头的是 tokens 已给出达标变体、只等平台切换的条目（输出里单独计数）。已达标的 ALLOW 条目会报 STALE，修好后记得删。
- `apps/android/…/ZColors.kt` 若仍自带 `darkVariant()` 且与 `accent.*.base` 深色不一致，脚本打印 WARN（不失败）。
- 历史：浅色 `screen.t3` / `latency.unknown` 0.4→0.55、深色 `t3` 0.4→0.5，都是为了过这道线；改这些值之前先跑一遍脚本。

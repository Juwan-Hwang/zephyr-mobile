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

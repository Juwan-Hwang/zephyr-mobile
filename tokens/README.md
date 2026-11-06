# tokens

- 桌面来源：`vendor/zephyr/packages/tokens/src/*.json`（子模块，只读，不改）。
- 移动增补：`mobile.json`（只放手机特有值；与桌面同名会直接报错）。
- 生成：`node tokens/build.mjs`（零依赖）→ `generated/ios/ZTokens.swift`、`generated/android/ZTokens.kt`。CI 用 `--check` 校验产物最新。**禁止手改产物。**

## 引用方式
- iOS（XcodeGen）：把 `../../tokens/generated/ios` 加进设计系统 target 的 `sources`。用法：`ZTokens.Colors.textPrimary`（动态色）、`.zType(ZTokens.TypeStyle.metric)`（随 Dynamic Type 缩放）、`ZTokens.LatencyThreshold.color(ms)`。
- Android（Gradle `:design`）：`kotlin.sourceSets["main"].kotlin.srcDir("$rootDir/../../tokens/generated/android")`（按 apps/android 实际层级调整）。用法：`CompositionLocalProvider(LocalZColors provides if (dark) ZColors.Dark else ZColors.Light)`，组件内 `LocalZColors.current.textPrimary`、`ZType.metric`、`ZLatency.color(ms, colors)`。包名 `com.zephyr.design.tokens`。
- 强调色：`ZTokens.Accent` / `ZAccent`（blue 默认，green / orange / pink）。紫色已废弃。

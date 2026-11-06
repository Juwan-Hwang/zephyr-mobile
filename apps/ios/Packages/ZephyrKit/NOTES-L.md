# NOTES-L · 资料库 / 节点 / 规则 / 订阅 / 设置 / 引导（ZephyrFeatures）

分支 `agent/ios/pages`（基于 main a8a8732），未 commit。只改了 `ZephyrFeatures/` 下的
`Subscriptions/ Settings/ Onboarding/ Library/ Rules/ Nodes/` 与 `App/RouteDestination.swift`。
Linux 沙箱只做了 `swiftc -parse`（全部通过），**没有类型检查 / 没在 Xcode 编译过**——首次 macOS CI 请把报错回传给 L。

## 公开签名

```swift
// 订阅（原型 24）
public struct SubscriptionsView: View {
    public init(engine: any ZephyrEngine, now: @escaping @Sendable () -> Int64 = { ZFormat.nowMillis() })
}
// 设置（原型 25）
public struct SettingsView: View { public init(engine: any ZephyrEngine) }
// 资料库（原型 13）
public enum LibraryItem: Hashable, Sendable { case nodes, subscriptions, rules, scenes, settings }
public struct LibrarySheet: View { public init(engine: any ZephyrEngine, onOpen: @escaping (LibraryItem) -> Void) }
// 引导（原型 01 / 02）
public enum OnboardingChoice: String, Sendable, Hashable, CaseIterable { case simple, best }
public struct OnboardingView: View {
    public init(engine: any ZephyrEngine, onFinish: @escaping () -> Void)                       // X 的快照用这个
    public init(engine: any ZephyrEngine, onFinishChoosing: @escaping (OnboardingChoice) -> Void)
}
// 已有，签名未变
public struct RulesView: View { public init(engine: any ZephyrEngine, query: String? = nil) }
public struct NodesView: View { public init(engine: any ZephyrEngine, query: String = "") }
```

所有 View 结构体标了 `@MainActor`；模型（`SubscriptionsModel` / `SettingsStore` / `LibraryModel` / `RulesModel` / `NodesModel`）
都是 `@MainActor @Observable final class`，只依赖 `any ZephyrEngine`。

`RouteDestination` 已全部接上：`.rules → RulesView`、`.subscriptions → SubscriptionsView(engine:now: model.now)`、
`.settings → SettingsView`；`LibraryDestination → LibrarySheet`，`onOpen` 映射为
nodes/subscriptions/rules/settings → `model.push(...)`，scenes → `model.present(.scene(id: 第一个场景))`。`RoutePending` 已删除。

## 页面要点

- **订阅**：`List(.insetGrouped)` + `zCardListRow()`（ZCardFill 底 + borderSubtle 分隔），页头 214 / “个 · 每 n 小时更新”，
  diff 卡（最近一次带 lastDiff 的订阅），流量卡用 `ZProfileCard`（7 天内到期或用量 ≥ 80% 为警告色），“其他 212 个 ›” 进入
  `SubscriptionsAllView`（可搜索）。左滑 = 更新 / 删除（删除先确认）；下拉 = 更新全部；右上 “+” = 四种导入方式（复用
  `SubscriptionImportFlow`）。**更新前显示更改** 开启时：单个先 `previewUpdate`，全部则逐个 `previewUpdate`（并发 6）合计后弹
  `SubscriptionReviewSheet`，确认后才 `updateSubscription` / `updateAll`。结果、错误一律 `ZToast`。
- **设置**：连接（按需连接 / 受信任的 Wi‑Fi › / 本地代理端口 ›）、检测（仅 Wi‑Fi 测速 / 结果保留）、存储（双段 ZProgressBar）、
  外观（外观 跟随系统/深色/浅色 + 强调色 4 选 1）、隐私、页脚 + 版本号。全部经 `SettingsStore` 全量 `updateSettings(patch:)`，
  乐观更新，失败回滚并吐司。子页 `TrustedWifiView`、`LocalProxyView`。
- **资料库**：`ZSheet("资料库")` + 2×2 `LibraryStatCard`（ZBigNumber .small）+ 4 行 `ZSettingsRow`。数字来自
  `nodeIndex().total` / `subscriptions` 流 / `ruleStats().total` / `scenes` 流，中文紧凑：**1,311 万 / 214 / 1.04 亿 / 3**
  （`CompactCount.zh`，已在 Linux 单独验证），VoiceOver 读完整千分位数字。AX 尺寸改为单列。
- **引导**：两步，`ZBrandMark(.mark)` → “1 / 2 添加订阅”+ 导入列表 → 导入成功切到 “2 / 2 已添加 X（n 个节点）· 选择使用方式”，
  简单 / 优选（默认优选）→ 继续。选“优选”时写回 `testOnWifiOnly = true`。
- **强调色**：页面自己读 `Settings.accent` 并 `.zAccent(...)`（`PageAccent.swift`；设置未到时沿用继承值），
  这样 Preview / 快照（X 的 `L2PagesSnapshotTests` 通过引擎设置 accent）不经 RootView 也正确。

## L* → Z* 替换

删除 `Library/Components/L*.swift` 全部 9 个（LAccentModifier / LDivider / LMeter / LPageHeader / LRow / LSearchField /
LSectionHeader / LStyle / LToggleRow）和 `Rules/RuleChainStepView.swift`。对应：
LDivider→ZDivider，LRow/LToggleRow→ZSettingsRow(+ZSettingsGroup)，LSectionHeader→ZSectionHeader，LSearchField→ZTextField，
LMeter→ZProgressBar，lCard→ZCard / zSurface，RuleChainStepView→ZChainStep，地区码文本框→ZFlag，LStyle.pageBackground→zPageBackground()。
没有 Z* 对应的页面级组合放在 `Library/Components/`：`PageHeader`（ZBigNumber 页头）、`PageFootnote`、`PageMetrics`（只由 tokens 组合）、
`MenuPickerRow`（ZSettingsRow + 系统 Menu 单选）、`PageAccent`。

## 需要 A（契约 / tokens）补充

1. **Settings.localProxyEnabled: Bool**：原型“本地代理端口 · 关”需要开关字段；现在行值只能显示端口号。
2. **隐私“共享诊断数据”**：契约无字段，暂用 `shareAnonymousPattern`（“分享今日卡片时附带图案”）占隐私分组。需要 `shareDiagnostics: Bool`。
3. **“应用图标 深色”**：需要 App 层备用图标资源 + `UIApplication.setAlternateIconName`（X），未做。
4. **引导“简单 / 优选”**：契约没有“设置场景默认来源（subscription_group / auto）”的写接口。现在只回调 `OnboardingChoice`，
   并在“优选”时写 `testOnWifiOnly`。建议加 `setSceneSource(source:)` 或 `Settings.sceneSourceDefault`。
5. **覆写规则写接口**（`RuleAddSheet` 的“添加”仍禁用）。
6. **批量预览**：“更新前显示更改 + 下拉更新全部”只能逐个 `previewUpdate`（214 次，真实引擎会各拉一次远端）。建议契约加
   `previewUpdateAll() -> SubscriptionDiff`，或让 `updateAll(dryRun:)`。
7. **tokens**：卡片 18pt 圆角（现用 `Radius.md + n1/2`）、引导选项 22pt（`overlay - n1/2`）、列表行最小高度 56 等仍是 token 组合；
   单选环粗细用 `radio * 0.32`（原型 7/22）。

## 需要 H / X 配合

- **H（RootView.SheetHost）**：资料库现在用 `ZSheet`（自带抓手 + “完成”），请把 `.library` 分支的
  `.presentationDragIndicator(.visible)` 等三行换成 `.zSheetPresentation(detents: [.medium, .large])`，否则会出现两个抓手。
- **X**：`L2PagesSnapshotTests` 的签名与上面一致，可去掉 `#if ZEPHYR_L2_PAGES`。引导快照只覆盖第 1 步（第 2 步的 internal
  `init(engine:added:onFinish:)` 只给 Preview 用）。App 首启判断（无订阅 → OnboardingView）放在 App target。
- Wi‑Fi 名称只能手动输入；读当前 SSID 需要 `NEHotspotNetwork.fetchCurrent` + 定位授权（App 层）。

## 未完成 / 已知风险

- 未编译。订阅页 List 的分组圆角是系统 insetGrouped 的（约 10pt），与原型 18pt 不同；若要完全一致需改成 ScrollView + 自绘左滑。
- `MenuPickerRow` 依赖 `Menu` + `.menuStyle(.button)` + `.buttonStyle(ZRowButtonStyle())` 让整行可点，需真机确认行高与高亮。
- `LocalProxyView` 在 `ZTextField` 外层加 `.keyboardType(.numberPad)`，依赖该修饰符向内传递。
- 删除没有撤销（契约无恢复接口）。

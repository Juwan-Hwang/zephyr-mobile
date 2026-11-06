# NOTES-H · 首页 / 场景 / 指令 / 活动（最近连接 · 连接轨迹 · 今日）

分支 agent/ios/pages（基于 main a8a8732），未 commit。H2 只改了 `Sources/ZephyrFeatures/` 下的
`App/`（不含 `RouteDestination.swift`）、`Home/`、`Scene/`、`Command/`、`Activity/`，以及新增 `Tests/ZephyrFeaturesTests/` 与本文件。
沙箱是 Linux：SwiftUI 无法编译。纯逻辑文件已用 swiftc（Swift 6.1.2，`-swift-version 5 -strict-concurrency=complete -warnings-as-errors`）编译并跑通 34 个 XCTest；
SwiftUI 文件只做了 `swiftc -parse` 语法检查，**首次 Xcode 编译请 X 回传报错**。

A 的 CI 修复全部保留：`App/SceneAlias.swift`（模块内 `typealias Scene = ZephyrKit.Scene`）、颜色走 tokens（`screenGreen` 经 D 的 `ZSwitchColor.on`）、`Activity/` 里的 ConnectionsSheet / TodayCardView 名字仍可用。

## 目录
```
App/        AppModel(+Actions/+Navigation/+Streams/+Preview) · RootView(SheetHost/ErrorBanner) · Route · DeepLink · RateRing · TrafficStore
            ErrorText · Haptics · HMetrics · RegionName（新）· SceneAlias（A）· RouteDestination（L2，未动）
Home/       HomeView · HomeHeader · HomeHero(+ConnectionDuration) · TrafficPanel · TrafficChart · ScenesSection · SceneRow(+Parts)
            SceneChangeConfirm(+ExitIPLine) · GlobalModeCard · SubscriptionsSection · HomeDock · HorizontalPanOverlay
Scene/      SceneSheet · SceneCandidateRow · SceneFunnel
Command/    CommandView · CommandModel · CommandResults · CommandPreviewCard · CommandTokenizer
Activity/   ActivitySheet（刚才 ↔ 轨迹）· RecentHost（聚合，纯逻辑）· RecentHostRow
            TraceView · TraceSteps（纯逻辑）· TraceOverrideSection（禁用，见下）
            TodayCardView · TodayCard · TodayTheme · WindArt（Canvas 流线）
            ConnectionsSheet（兼容名，转发到 ActivitySheet，供 X 的 ActivitySnapshotTests）
```
`Connections/`、`Today/` 原为空目录，已删除；全部落在 `Activity/`。

## 本轮改动（H2）
1. **临时组件 → D 的 Z\***，旧文件已删：
   `HFlag`→`ZFlag`（`isHighlighted` = 滑动跨地区跳动）· `HConnectSwitch`→`ZConnectButton`（`ConnectionStatus.connectPhase` 映射，failed = off）·
   `UndoToastView/UndoToastHost`→`ZToast`（`.zToast($model.toast)`）· `UsageBar`→`ZProgressBar(value:tone:)` ·
   `SheetHeader`→`ZSheet` · `HomeSectionHeader`→`ZSectionHeader`（`.homeSectionInsets()` 对齐原型 22/30）· dock→`ZSearchBar(onTap:libraryAction:)`。
   删除：`Home/HFlag.swift`、`Home/HConnectSwitch.swift`、`Home/UndoToastView.swift`、`Scene/SheetHeader.swift`；HMetrics 里对应的 flag/switch/toast 常量一并删除。
2. **@MainActor**：App/Home/Scene/Command/Activity 下所有 `View` / `ViewModifier` / `UIViewRepresentable` 结构体都标了 `@MainActor`（44 个）；
   AppModel、CommandModel、TrafficStore 本来就是 `@MainActor`。Canvas 渲染闭包只捕获值类型（TrafficChart 快照、WindArt 加锁缓存），不读 @State。
3. **Activity 按原型 08/09/14 重做**（见下节）。
4. **Bug 修复**（单测发现）：
   - `DeepLink.url`：`URLComponents.queryItems` 不转义 `&`/`=`/`+`，`zephyr://command?q=a&b=c` 读回成 "a"。改为严格转义 + `percentEncodedQueryItems`。
   - `CommandTokenizer`：两字母码只看第一次出现，"disney plus us" 里 "plus" 的 us 被跳过后不再找后面的独立 "us"。改为找第一个独立出现；两字母服务别名（tg）同样要求独立。
5. 吐司数据模型：`AppModel.toast` 从自定义 `UndoToast` 改为 D 的 `ZToastItem?`；写操作统一用 `showUndo(_:undo:)`。

## 公开 API（ZephyrFeatures，给 App target / X / L）
```swift
// 入口
public struct RootView: View { public init(model: AppModel) }          // NavigationStack + sheet + 指令层 + 错误横幅
public struct HomeView: View { public init() }                          // 需要 .environment(AppModel)

@MainActor @Observable public final class AppModel {
  public init(engine: any ZephyrEngine, now: @escaping @Sendable () -> Int64 = ZFormat.nowMillis)
  public static func preview(connected: Bool = true, mode: ProxyMode = .rule, frozen: Bool = false) -> AppModel  // MockEngine（frozen = 9:41）
  // 只读状态
  public let engine: any ZephyrEngine; public let now: @Sendable () -> Int64; public let traffic: TrafficStore
  public internal(set) var connection, scenes, subscriptions, usage, settings, globalNode, retesting, regionChoices, pendingChange
  public var lastError: ZephyrError?; public var toast: ZToastItem?
  // 导航
  public var path: [Route]; public var sheet: SheetRoute?; public var isCommandPresented: Bool; public var commandPrefill: String
  public var beforeConnect: (@MainActor () async throws -> Void)?      // App 层启动 NE / VPN 授权
  public func present(_: SheetRoute); dismissSheet(); push(_: Route); popToHome(); openCommand(prefill:); closeCommand()
  @discardableResult public func handle(url: URL) -> Bool; public func open(_: DeepLink)
  // 生命周期
  public func start(); stop(); scenePhaseChanged(_: ScenePhase); refreshUsage() async
  // 写操作（全部 async，错误进 lastError）
  public func toggleConnection() async; connect() async; disconnect() async; setMode(_:) async
  public func setGlobalNode(_: NodeSummary) async -> ExitChange?; globalAlternatives() async -> [NodeSummary]
  public func loadRegionChoices(sceneId:) async; sceneCandidates(_:region:) async -> [NodeSummary]
  public func beginSceneChange(sceneId:to:) async; cancelPendingChange(); confirmPendingChange() async
  public func applySceneChange(sceneId:from:to:) async; retest(sceneId:) async
  public func showUndo(_ message: String, undo: (@MainActor @Sendable () async -> Void)? = nil); dismissToast()
  public var isConnected: Bool; isOn: Bool; scenesTestedText: String?; func scene(id:) -> ZephyrKit.Scene?
}
public enum Route { case nodes(query:), rules(query:), subscriptions, settings }
public enum SheetRoute { case library, scene(id:), connections(traceID:) /* traceID = 域名 */, today }
public enum DeepLink { init?(url:); var url: URL; static let scheme = "zephyr" }   // 见 DeepLink.swift 头注释
public struct RateRing / RatePoint; public final class TrafficStore; public extension ZephyrError { var userMessage: String }
```
内部但跨页可用：`HRegionName.name(_:)`、`ExitIPLine`、`HHaptics`、`HMetrics`、`HPreview`。

## Activity（原型 08 / 09 / 14）
- **刚才**（`ActivitySheet`）：订阅 `activeConnections()`，`RecentHost.aggregate` 按域名聚合（小写、最近活跃在前、≤ 50），行 = 域名 + "AI，US-Fixed-01"/"直连" + 等宽流量 + ›；
  底部"iPhone 看不到是哪个 App 发起的，只能显示域名。"；长按 = 关闭该域名的全部连接（`closeConnection`）。轻点 → 同一 sheet 内切到轨迹，有"‹ 刚才"返回；深链 `zephyr://connections/<host>` 直达轨迹。
- **连接轨迹**（`TraceView`）：大字域名 + "3 秒前 · 17 个连接 · 2.1 MB"；`ZChainStep(style: .regular)` 四步 **规则 → 场景 → 节点 → 出口**，数据由 `TraceSteps.build` 从
  `testRule(input: host)` + `ruleStats().layers`（"来自 Nebula Cloud"）+ 场景（`RuleTrace.scene` 或按 policy 查）+ 最近活动连接的 node（命中场景例外 → "Claude 例外 · 固定"，且不冒用场景出口 IP）拼出；
  DIRECT → 规则 → 出口"直连"；REJECT → 规则 → "已拦截"（红点）。逐步淡入（80ms + 60ms·i）+ 竖线流动光（原型 `.rail i`），Reduce Motion 下关闭。
- **本次覆写 / 始终应用**（`TraceOverrideSection`）：版式照原型（分段 不变/直连/其他场景 + "始终应用"开关），**整体禁用 + 55% 透明 + "此版本暂不支持为单个域名更改路由。"**，因为 Swift 协议没有 `overrideHost` / `hostOverride`。补上后的接法写在该文件头注释。
- **今日**（`TodayCardView` + `TodayCard`）：`WindArt` 逐行移植原型 `windArt()`（LCG、N = 150 + 4WH/5000、3.2pt 步长、左下→右上渐变、t += 0.006/帧），已用 Python 同公式渲染核对与 today.png 一致；
  "由今天的流量生成"：每条线按起点高度映射到 24 小时，透明度 × (0.35…1) 的该小时流量相对值。三套主题 夜 #02040a / 晨 #F6EEE6 / 雾 #ECEDEF（`TodayTheme`，@AppStorage 记忆）。
  1.8 GB 大数字（`ZFormat.bytesParts` + `.zDisplay(.hero, weight: .thin)`）与三项统计（个地区 / 小时在线 / ms 最快）、品牌字标、"今日"。
  **分享** = `ShareLink(item: Image)`，图片由 `ImageRenderer` 按 346×500 ×3 渲染（流线静止在 t = 0）；**存储图像** = PhotoKit 仅添加（PNG 数据）。动画 30fps 上限、`Canvas(rendersAsynchronously:)`；Reduce Motion 静止。

## 测试（Tests/ZephyrFeaturesTests/）
`RateRingTests`(10) · `DeepLinkTests`(8) · `CommandTokenizerTests`(8) · `RecentHostTests`(3) · `TraceStepsTests`(5)，全部 `@testable import ZephyrFeatures`。
**Package.swift 需要主 agent 在 Apple 平台分支里加测试目标（H 没改 Package.swift）**：
```swift
#if !os(Linux)
targets += [
    .target(name: "ZephyrDesign", …),
    .target(name: "ZephyrFeatures", …),
    .testTarget(name: "ZephyrFeaturesTests", dependencies: ["ZephyrFeatures", "ZephyrKit"]),
]
#endif
```
Linux 上 SwiftPM 不会编这个目录（未声明的测试目录被忽略），所以不影响 K 的 `swift test`。
沙箱验证方式（不走 swift build）：`/workspace/projects/dd0b68e2-d758-41f7-bee8-55242193b21f/work/h2-tests/run.sh`
——先编 ZephyrKit 模块，再把 `RateRing / DeepLink / Route / RegionName / CommandTokenizer / RecentHost / TraceSteps` 编成 `ZephyrFeatures` 模块（-enable-testing），自动生成 XCTMain 后运行：**34/34 通过**。
（该脚本需要 libc6-dev 头文件；沙箱重置后先 `sudo apt-get install -y gcc libc6-dev`。）

## 需要 A 补的契约（Swift 协议 ZephyrEngine 目前没有）
| # | 用途（原型） | 建议签名 | 现在的退路 |
|---|---|---|---|
| 1 | 场景检测进度（10 检测中："9 个可用 · 检测中" + 确定进度条） | `sceneProbes() -> AsyncStream<[SceneProbe]>`；`record SceneProbe { sceneId, tested: Int32, total: Int32, startedAt: Int64 }` | `ProbeBar` 不确定进度，只在本机发起 `retestScene` 期间显示 |
| 2 | 场景详情漏斗（06："检测自 2 个订阅中的 512 个节点"、按服务"可访问 GPT / Claude / Gemini"） | `sceneFunnel(sceneId) async throws -> SceneFunnel { subscriptions: Int32, totalNodes: Int64, steps: [FunnelStage { label: String, count: Int64 }] }` | 用 ≤ 50 个候选推三级：全部候选 → 延迟 < 300 ms → `Scene.available` |
| 3 | 场景来源分段（06：订阅分组 / Zephyr 优选） | `setSceneSource(sceneId, source: SceneSource, group: String?) async throws -> Scene` | 分段只读（`.disabled`） |
| 4 | 全局模式换节点（12：建议节点 + "所有 App 的出口都将变为…"） | `globalCandidates(region: String?) async throws -> [NodeSummary]`（按延迟，≤ 50）+ `previewGlobalChange(nodeId) async throws -> ExitChange` | 合并各场景候选去重排序；`setGlobalNode` 只在应用后才返回 ExitChange，确认卡没有出口 IP 预览 |
| 5 | 指令 switch_node 负载（07："Gemini 走日本"落到哪个场景） | 固定 `payload = "<sceneId>:<nodeId>"`，全局为 `"global:<nodeId>"`；Mock 同步 | CommandModel 5 级推断（payload 前缀 → 输入里的服务 → 标题前缀 → 候选池包含 → 全局） |
| 6 | 连接轨迹 / 覆写（08/09，契约 §13 已定义但未进 Swift 协议） | `recentHosts(limit:) -> AsyncStream<[ConnectionInfo]>`、`connectionTrace(host:) async throws -> ConnectionTrace`、`overrideHost(host:target:sceneId:persistent:) async throws`、`hostOverride(host:) async -> TraceOverride?`，以及 `ConnectionTrace / TraceTarget / TraceOverride` 记录 | 刚才 = activeConnections 聚合；轨迹 = testRule + ruleStats + scenes 拼（缺"经由 US Fixed IP"、"7 天未变化"、ruleSource 精确值）；覆写 UI 禁用 |

另需 A：tokens 里没有今日卡片的艺术色板（`TodayTheme` 内注明出处，建议 `art.today.{night,dawn,mist}.{bg,stroke0..2,ink}`）；HMetrics 里剩余原型尺寸（homeInset 22、cardRadius 22、chartHeight 150、todayCardRadius 32 等）。

## 需要 X（App target）配合
- **Info.plist 加 `NSPhotoLibraryAddUsageDescription`**（"存储图像"）。缺失时代码会提前判定失败并提示，不会崩溃，但功能不可用。
- `ActivitySnapshotTests` 仍可用 `ConnectionsSheet(initialTraceID:)`；建议改为 `ActivitySheet(initialHost:)` 并加轨迹快照 `ActivitySheet(initialHost: "claude.ai")`、今日三主题快照（`TodayCard(usage:dateText:theme:animated: false)`）。
- 快照前关动画：TodayCard 用 `animated: false`；轨迹的逐步淡入在 Reduce Motion 下直接显示。

## 未完成 / 已知缺口
- 未在 Xcode 编译过（见文末风险）。
- 覆写 UI 禁用（契约 #6）；轨迹"x 天未变化"、"经由 …"缺数据。
- 指令输入框仍是 H 自己的镜像下划线输入（ZSearchBar 输入模式不支持按 token 下划线），任务只要求 dock 换 ZSearchBar。
- `ZSectionHeader` 标题是 t3 常规字重，原 HomeSectionHeader 是 t2 中等字重——按 D 的组件走，和原型 `.sec b` 有细微差异。
- 今日大数字用 `.hero`（76pt），原型 84pt；卡片是定比例图片，字号封顶 xLarge（VoiceOver 标签给出全部信息）。
- `ProbeBar` 仍是不确定进度（契约 #1）。
- 场景详情漏斗是推算的三级（契约 #2）。

## 风险最大的 API 调用（首次编译 / 真机请重点看）
1. `ImageRenderer(content: TodayCard(…animated: false))` → `uiImage`：内容含 `Canvas`、`ZBrandMark`（asset 矢量）、`.environment(\.colorScheme)`。非动画路径已去掉 TimelineView/GeometryReader，但仍需真机确认 Canvas 与资产在 ImageRenderer 中正常出图（`proposedSize` = 346×500，scale 3）。
2. `PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data:options:) }`（async throws）：依赖 Info.plist 键与"仅添加"授权；Swift 6 SDK 下 changeBlock 为 @Sendable，只捕获 `Data`。
3. `.zToast($model.toast)` + `ZToastItem(action:)` 同步闭包里 `Task { @MainActor in await undo() }`：`showUndo` 的 undo 签名是 `@MainActor @Sendable () async -> Void`，严格并发下应无告警，但这是首页撤销链路的唯一入口。
4. `Canvas(rendersAsynchronously: true)`（WindArtCanvas）：渲染闭包在后台线程执行，只碰 `WindArtCache`（NSLock）与值类型；若 SDK 把 renderer 视为 MainActor 隔离，可能出现隔离告警——退路是改成 `false`。
5. `engine.testRule(input: host)` 用作轨迹：它回答"规则会怎么匹配这个域名"，不是"这条连接实际怎么走"；与 `ConnectionInfo.scene/node` 不一致时以活动连接的 node 为准（例外节点），场景以规则为准。契约 #6 落地后应换成 `connectionTrace(host:)`。
6. `ZSheet` + `.zSheetPresentation()`（隐藏系统抓手、D 自绘抓手）；资料库（L）仍用系统抓手。sheet 内强调色由 RootView 显式传入 `SheetHost(accent:)`。

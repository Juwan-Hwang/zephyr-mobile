# NOTES-D · ZephyrDesign（设计系统）

分支 agent/ios/foundation，未 commit。只写了 `Sources/ZephyrDesign/`（删除了 Placeholder.swift；`Generated/ZTokens.swift` 符号链接未动）。
沙箱无法编译 SwiftUI：全部代码按 iOS 17 / Swift 5.10 逐行人工核对 API，**首次在 Xcode 编译时请 X 留意报错并回传给 D**。

## 目录
```
ZephyrDesign/
  Foundation/   ZAccent（ZAccentKey/.zAccent/ZAccentStyle）· ZMotion · ZFill（组合语义填充）· ZTextStyles（.zMono/.zDisplay）
                ZPressStyle（按下缩放+触感）· ZRowButtonStyle · ZMetrics（待 token 化的原型尺寸，internal）· ZPreviewSupport（DEBUG）
  Components/   ZSurface ZCard ZButton ZIconButton ZToggle ZSegmented ZTextField ZBadge ZLatencyPill ZProgressBar
                ZSheet ZToast ZEmptyState ZSkeleton  + ZDivider ZStatusDot ZBrandMark
  Business/     ZConnectButton ZTrafficStat ZSparkline ZNodeRow ZGroupCard ZProfileCard ZFlag ZSettingsRow
                ZSectionHeader ZChainStep ZSearchBar  + ZSettingsGroup（ZBigNumber 在 Components）
  Resources/Brand.xcassets   ZephyrMark / ZephyrLockup（模板矢量 SVG，来自 design/prototype/brand + 原型 zlock 路径）
```
每个组件一个文件，均带 `#Preview`：深色 / 浅色 / 强调色（4 色矩阵）/ AX5。组件是纯视图，不依赖引擎，所以预览不注入 MockEngine。

## 约定（给 H / L / X）
- 强调色：根视图 `.zAccent(accent)`（同时设置 `.tint`）。组件内取 `@Environment(\.zAccent)` 或用 `ZAccentStyle()` 作 ShapeStyle。
- 页面底色：`.zPageBackground()`（深色纯黑 / 浅色 #F2F2F7）。
- 卡片列表：`ZCard(padding: 0) { VStack(spacing: 0) { row; ZDivider(); row } }`；设置页用 `ZSettingsGroup("标题") { … }`。
- 行可点：`Button { } label: { ZGroupCard(…) }.buttonStyle(ZRowButtonStyle())`；其他可点：`.buttonStyle(ZPressStyle())`。
- 字：比例字用 `.zType(...)`（A）；等宽 `.zMono(.body)`；大数字 `.zDisplay(.large)` 或直接 `ZBigNumber`。
- 动效：`ZMotion.micro/standard/slow/page/spring`（全部来自 ZTokens.Time/Easing/Motion）；`ZMotion.gentle(_:reduceMotion:)`、`ZMotion.motion(_:reduceMotion:)`。
- 文案：UI 标签参数是 `LocalizedStringKey`，在**主 bundle** 查找 → `Localizable.xcstrings` 请放在 App target（X）。数据字符串参数是 `String`（或 `verbatim:` 版本）。
- 数字格式化不在组件内做：调用方用 `ZFormat`（K）后传字符串；`ZRateText(ZFormat.rate(bps))` 直接接元组。
- ZSparkline 性能：外面加 `.equatable()`；平滑滚动用 `TimelineView(.animation)` 只驱动 `scrollPhase`，每来一个采样把数组左移一格并把 phase 归零。只重画这一个 Canvas。
- ZNodeRow 固定高：`ZNodeRow.height(for: dynamicTypeSize)`（52 / AX 66），行内字号封顶 AX2，AX 尺寸隐藏协议（同原型 xl）。
- ZToast：`.zToast($toastItem)` 挂在首页根上；`toastItem = ZToastItem("已换到 东京 03", actionTitle: "撤销") { … }`，默认停留 ZTokens.Motion.undoWindow。
- ZSheet：`.zSheet(isPresented:) { ZSheet("场景") { … } }`（自带抓手、标题、“完成”=dismiss、强调色透传、圆角 sheetRadius）。自行 `.sheet(item:)` 时用 `.zSheetPresentation()`。

## 与原型/token 的差异（判断）
1. **延迟着色**：按任务要求用 `ZTokens.LatencyThreshold.color`（<80 绿 / 80–199 黄 / 200–399 橙 / ≥400 红）。原型节点页只把 >200ms 标黄、其余灰。若产品要原型的“克制”版本，请 A 调整阈值/颜色或让我加 `.quiet` 着色模式。
2. **开关绿**：原型 --green #30D158 ≈ `ZTokens.Colors.latencyGood`（#34C759），`ZSwitchColor.on` 借用它；`colorSuccess`（#4ADE80）太亮不像系统开关。
3. **ZConnectButton**：原型首页是 66×40 的大号开关，不是 168pt 圆钮；`ZTokens.Layout.connectButton(168)` 未使用。光晕颜色 = 填充色（默认绿；`tint: .accent` 时为强调色）。
4. **大数字字重**：ZTokens.metric 是 `.ultraLight`（100）；原型 CSS 是 200（≈ SwiftUI `.thin`）。我跟随 token，建议 A 改成 `.thin`。
5. **卡片表面**：深色 surfaceRaised（.55 透明）在纯黑上几乎不可见，层次主要靠 1px borderSubtle（与原型一致）；浅色用 surfaceElevated（白），因为 surfaceRaised 浅色是 4% 黑，会变成灰卡。在 `ZCardFill` 里组合，组件不写三元。
6. 原型 sheet 圆角 34，token sheetRadius 24 → 用 token。

## 需要 A 补的 token（目前在 ZMetrics / ZFill 里临时定义，补齐后只改这两个文件）
- 颜色：`surfaceCard`（深 surfaceRaised / 浅 surfaceElevated）、`fillTrack`（--s3）、`fillKnob`（--s4）、`textQuaternary`（--t4 20%）、`bgPage`（#000 / #F2F2F7）、`switchOn`。
- 字阶：`mono`（13）、`monoSm`（12）、`monoXs`（10.5）、`monoLg`（15）；`displayHero 76`、`displayLarge 56`、`displayTitle 44`、`displaySmall 30`；display 字距 -0.04em。
- 尺寸：connect 66×40/旋钮 34、button 40/52、iconButton 36/52、segment 34、field 40/48、dock 52、flag 20×28 r5、tag r4、toast 52 r18、grabber 36×5、chainDot 9/11、rowHeightAX 66、latencyColumn 52、settingsRowMin 56。
- Motion 已足够（micro/standard/slow + spring cubic-bezier(0.16,1,0.3,1)），无需新增。

## 已知缺口
- 未在 Xcode 编译/运行过（Linux 沙箱）。重点风险点：自定义 `ShapeStyle.resolve(in:)`（iOS 17）、`AccessibilityNotification.Announcement(String)`、`sensoryFeedback(_:trigger:condition:)`、`.fontWeight` 叠加 `.zType`。
- 资源：Brand.xcassets 里是 SVG（Xcode 12+ 支持，preserves-vector-representation + template）。未放字体文件——全部用 SF Pro / SF Mono 系统字。
- ZChainStep 没做原型轨迹竖线上的“流动光点”动画（`.rail i`），也没做逐步入场；入场由 H 用 `.transition` 做。
- ZSegmented 在 AX 尺寸且 >2 段时改为纵向；没有用 ViewThatFits（matchedGeometryEffect 在 ViewThatFits 的多候选里会冲突）。
- 快照测试（X）：建议对每个组件跑 深/浅 × 4 强调色 × {large, accessibility5}，组件都无内部随机/时间依赖（ZSkeleton 扫光与 ZToast 进度条是动画，快照前用 `.transaction { $0.disablesAnimations = true }`）。

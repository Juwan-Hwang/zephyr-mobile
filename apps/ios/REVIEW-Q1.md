# REVIEW-Q1 · Zephyr iOS 对照原型审查（Q，只读）

- 分支：`agent/ios/pages` @ `bce4fa5`（工作区干净，本文件是唯一新增，未 commit）
- 验收标准：`design/prototype/`（index.html 内联 CSS/JS、pages.js、`shots/*.png` 35 张逐张查看）、`design/notes/mobile-design-spec.md`、`tokens/mobile.json`
- 范围：`Packages/ZephyrKit/Sources/ZephyrDesign`、`ZephyrFeatures`、`apps/ios/Widgets`（顺带 `App/` 中与 UI 直接相关的部分）
- 方法：静态审查。**没有 Xcode / 模拟器**，未实际编译运行、未跑快照；性能结论来自代码路径分析，需用 Instruments 复核。
- 行号均以当前提交为准。原型尺寸以 CSS px = pt 计。

## 修复进度（B 维护）

- 2026-11-07 PR agent/ios/review-q1：✅ P0-1、P0-2（组件与全仓颜色改 screen.*，sheet 内卡片自动用 s2）、D-P1-1、D-P1-2、H-P1-1、H-P1-4、H-P1-8、H-P1-9、L-P1-3、L-P1-4、W-P1-1、L-P1-2、H-P1-7（部分：导出去抖 + PNG 离主线程）、H-P1-3（可横滑行）；顺带 D-P2-1/2、D-P2-4（触感）、H-P2-5、W-P2-1/2/4。
- 2026-11-08 PR agent/ios/review-q1b：✅ H-P1-2（场景行 ≥xxxLarge 堆叠）、L-P1-1（从资料库进入的页面返回时重开资料库，返回标题“资料库”）、W-P1-2（小组件速率下标注“x前”，偏离设计的说明见 NOTES-X）。
- 同 PR 另修 H-P1-6（指令框改 UITextField 属性下划线，拼音组合期间不回写）。待做 P1：仅 H-P1-5（需契约 Scene.services）；真机验证待做（拼音、光标）。

- 2026-11-08 PR agent/ios/review-q1c：✅ D-P2-8（分区标题 t2/500）、H-P2-12（轨迹流光 30fps）、H-P2-17（指令框聚焦补一拍）、L-P2-6（延迟阈值 ≥）、L-P2-9（地区 chip 触感只触发一次）。其余 P2 持续按批处理；需视觉核对的项等快照图（CI 目前不上传 __Snapshots__）。
- 2026-11-14 复核：其余条目的修复记录统一见 REVIEW-Q2.md（含 H-P2-21 深链来源确认 / DeepLinkPolicy、H-P2-22）。代码核对后 Q1 仅 D-P2-10 保留为已记录的限制；H-P1-5 已随契约 §14.z Scene.services 落地（Home/SceneServices.swift）。

## 总览

| 级别 | 条数 | 含义 |
|---|---|---|
| **P0** | 2 | 发布阻断：验收主路径缺失，或全局性偏离原型 |
| **P1** | 17 | 明显的体验 / 视觉 / 性能 / 无障碍问题，上线前应修 |
| **P2** | 55 | 打磨项，对标一线 App 应做 |

整体评价：架构与性能意识很好（高频流量隔离到 TrafficStore、节点列表 UIKit 虚拟化、Reduce Motion 基本全覆盖、VoiceOver 标签普遍认真）。差距主要集中在三处：**① 设计系统没有用原型的手机实色色板（`screen.*`），导致全局偏色、sheet 内层级反转；② 首页场景行脱离了 ZGroupCard，丢掉了大字体堆叠与按压反馈；③ 若干“契约未就绪”的功能以禁用 UI 形式上线（死路）。**

---

## P0

### P0-1 〔Library/Onboarding〕引导页从未接入 App
- 文件：`ZephyrFeatures/Onboarding/OnboardingView.swift`（整页已实现）；`App/ZephyrApp.swift:27-31`、`ZephyrFeatures/App/RootView.swift:20-44`
- 问题：全仓只有 `SnapshotTests/Cases/L2PagesSnapshotTests.swift:42` 引用 `OnboardingView`。没有任何首启判断，新用户（无订阅）直接落在首页，原型 01–03（ob1.png / ob2.png）完全不可达；首页空态只有一句“添加订阅后，这里会显示…”（`ScenesSection.swift:21`）。
- 建议：在 `RootView` 增加首启门控：`subscriptions` 流首帧为空且 `@AppStorage("onboarding.done") == false` 时 `fullScreenCover` 呈现 `OnboardingView(engine:onFinishChoosing:)`；完成后置位并按 choice 设置场景来源。引导第 3 步（连接 / VPN 授权）衔接首页未连接态，并在首次点开关时再请求 VPN 配置，而不是启动即弹。

### P0-2 〔Design〕组件没有使用原型的手机色板 `screen.*`，全局偏色且 sheet 内层级反转
- 文件：`ZephyrDesign/Foundation/ZFill.swift:9-45`、`Components/ZSheet.swift:111`、`Components/ZToast.swift:68`、`Components/ZSurface.swift:39-47`，以及全仓 `textDanger / textSuccess / textWarning / colorWarning / colorDanger / colorSuccess` 的 40 处引用
- 问题：`tokens/mobile.json` 已经按原型 `:root` / `.device.light` 生成了 `ZTokens.Colors.screenS1…S4 / screenHl / screenHl2 / screenT1…T4 / screenGreen / screenAmber / screenRed / screenGlass / screenUp`（`Generated/ZTokens.swift:52-85`），但全仓只用了 `screenGreen` 1 次；组件仍用桌面玻璃 token：
  - 卡片 `ZCardFill` 深色 = `surfaceRaised` rgba(12,12,16,**0.55**)；sheet 底 = `surfaceElevated` ≈ **#18181B**。原型是 sheet `--s1 #0C0C0E`，列表 `--s2 #141417`（**列表比 sheet 亮**）。现在 sheet 内的卡片（场景候选、最近连接、资料库统计、指令建议）**比 sheet 底还暗**，层级与 scene.png / act.png / lib.png 相反。
  - 语义色是 Tailwind：危险 #EF4444、成功 #4ADE80、警告 #F59E0B；原型是 Apple 系统色 #FF453A / #30D158 / #FFD60A（浅色 #FF3B30 / #34C759 / #FF9F0A）。可见处：订阅 diff “+1,204 / −318”（subs.png）、锁定小锁与琥珀进度条（home.png、global.png “周一到期”）、确认卡黄点（scrub.png）、“Claude 不可用”。
  - 吐司底 `surfaceElevated` 应为 `--s4 #26262B`；轨道 `ZTrackFill`= borderDefault（浅色带蓝灰 rgba(30,41,59,.14)）应为 `--s3`；`ZQuaternaryText` 浅色同样偏蓝；开关关态 `ZSwitchColor.off` = 20% 白应为 `--s4`；玻璃 `.glass` 应为 `screenGlass` rgba(28,28,32,.82)。
- 建议（一次改在 Design 层，页面不用动）：
  - `ZCardFill` → `screenS1`（首页卡片）/ 新增 `ZListFill` → `screenS2`（sheet 内列表、指令建议、资料库统计）；`ZTrackFill` → `screenS3`；`ZKnobFill` → `screenS4`；`ZQuaternaryText` → `screenT4`；`ZSwitchColor.off` → `screenS4`；分隔线 `ZDivider` → `screenHl`；描边 → `screenHl2`。
  - `zSheetPresentation` 的 `presentationBackground` → `screenS1`；`ZToast` 底 → `screenS4`；`ZSurface(.glass)` 与 `ZSearchBar` / `ZIconButton(.glass)` 的着色层 → `screenGlass`。
  - 新增 `ZTokens.Colors` 语义别名（或在 tokens 层把 `text*`/`color*` 的 mobile 覆盖值指向 `screen.red/green/amber`），把 `textDanger/textSuccess/textWarning/colorWarning/colorDanger` 全量替换。文字 `textPrimary/Secondary/Tertiary` 改用 `screenT1/T2/T3`（浅色原型是纯黑 90/58/40%，现在是 rgba(24,24,28,…)）。
  - 改完后用 home / scene / act / lib / subs / settings 的深浅色快照与原型并排比对。

---

## 一、Design 组件（D）

### P1
**D-P1-1 触感过度：几乎每次按下都在震**
- `Foundation/ZPressStyle.swift:26`（默认 `.light`）、`Foundation/ZRowButtonStyle.swift:9`（默认 `.selection`）、`Components/ZButton.swift:68`（primary `.medium`）、`ZSheet.swift:77`、`ZIconButton.swift:74`、`ZSectionHeader.swift:48`
- 问题：按下即触发（`ZHapticOnPress`），连“完成”“取消”、每一行列表、section 链接都震；Apple 自带 App 只在“状态改变/确认/选择变化”时给触感，普通导航按压不震。再叠加页面里的 `.sensoryFeedback`（HomeView 吐司 success、ZSegmented selection、MenuPickerRow、RegionChips），一次操作常有 2 次触感。
- 建议：`ZPressStyle` / `ZRowButtonStyle` 默认改 `.none`；只保留：连接开关（medium + 连上 success）、场景横滑跨格（selection）、分段/单选变化（selection）、确认破坏性或应用类操作（success/warning，在结果返回后触发而不是按下时）。

**D-P1-2 `ZSettingsRow` 把右侧可交互控件合并成一个无障碍元素**
- `Business/ZSettingsRow.swift:78`（`.accessibilityElement(children: .combine)` 包住了 `trailing`）
- 问题：`SettingsView.swift:100-102` 把 4 个强调色按钮放进 trailing，VoiceOver 下合并成一个元素，无法单独选中某个颜色；规则层的 ZBadge 没问题，但任何带按钮的 trailing 都会被吞。
- 建议：仅在 trailing 为纯展示时 combine；给 `ZSettingsRow` 加 `trailingIsInteractive` 参数（或检测到自定义 trailing 时改为 `.contain`，标题块单独 `.combine`）。

### P2
- **D-P2-1** `ZSheet.swift:71-73`：“完成”用 17 semibold 强调色；原型 `.sh-top .ibtn` 是 t2 常规字（scene.png、act.png、lib.png 均为灰色“完成”）。改 `.zType(.body)` + `textSecondary`。`ZSheet.swift:80-81` 标题栏左右 24 → 22（`.sh-top` padding 14 22），上 6 → 14。
- **D-P2-2** `ZSheet.swift:52-55`：顶部 1px 线是直线矩形，被 34pt 圆角裁切后两端断开；原型是跟随圆角的 `border-top`。改为 `UnevenRoundedRectangle(topLeading: 34, topTrailing: 34).stroke(screenHl2)` 叠在 presentation 背景上，或直接去掉（系统 sheet 已有层次）。
- **D-P2-3** `ZSheet` 只有 `LocalizedStringKey` 初始化：`SceneSheet.swift:38` 把用户数据 `scene.name` 包成 `LocalizedStringKey`，会进入本地化查表。补 `init(verbatim:)`。
- **D-P2-4** `Components/ZToast.swift:44`：消息 13 → 14（`.toast` 14px）；动作按钮 `ZPressStyle(haptic: .medium)`（:61）去掉触感。
- **D-P2-5** `Components/ZSegmented.swift:40,73,75`：外圆角 15 → 13、滑块圆角 12 → 10（`.seg` 13 / `.knob` 10），阴影 0.25 → 0.4；:53 无 label 时设置了空字符串 label，改为不设置。
- **D-P2-6** `Components/ZButton.swift:59`：regular 用 `button` 15/600，原型 `.btn` 14/500，按钮显得偏重；新增 `ZTokens.TypeStyle` 按钮档或 `.zType(.footnote)+.medium`。`:64` 最小高恒为 44（原型 40）可接受，但应把视觉高度保持 40、用 `contentShape` 扩触控区。
- **D-P2-7** `Foundation/ZTextStyles.swift:94`：所有大数字统一 −0.04em；原型状态字 −0.035、速率 −0.045、场景 76pt −0.05。给 `ZDisplaySize` 各自的 tracking。
- **D-P2-8** `Business/ZSectionHeader.swift:23-24`：标题应为 t2 / 500（`.sec b{font-weight:500;color:var(--t2)}`），附注 t3；现在两者同为 t3 常规（home.png “场景”“订阅”明显比右侧亮）。
- **D-P2-9** 组件库与页面分叉：`ZGroupCard`、`ZNodeRow`、`ZLatencyPill`、`ZTrafficStat`、`ZSparkline` 在 Features 中 **0 处使用**；`SceneRow`、`SceneCandidateRow`、`NodeCell`、`RecentHostRow`、Widgets `RegionBadge` 各自重写。结果是大字体堆叠、延迟阈值（见 L-P2-6）、徽标字号（W-P2-3）三处不一致。要么让页面改用组件，要么删掉未用组件，避免两套真相。
- **D-P2-10** `Package.swift:36`：声明了 `.macOS(.v14)`，但 `ZephyrDesign` 无条件 `import UIKit`（`ZFill.swift:6`、`ZTokens.swift:5`），在 Mac 上 `swift build/test` 会失败（CI 用 xcodebuild 所以目前没暴露）。去掉 macOS 平台或 `#if canImport(UIKit)`。
- **D-P2-11** `Components/ZTextField.swift:80`：父容器 `.onTapGesture { focused = true }` 会与 TextField 自身的点按定位光标竞争；改为 `.contentShape` + 只在 HStack 空白区（图标、padding）响应。
- **D-P2-12** `Components/ZSkeleton.swift:61-68`：`.mask(content)` 让内容渲染两次；规则页 8 行骨架（`RulesView.swift:70`）问题不大，但不要在长列表里用。

---

## 二、Home + Scene + Command + Activity（H）

### P1
**H-P1-1 撤销吐司与错误横幅被 sheet 盖住**
- `Home/HomeView.swift:42`（`.zToast` 挂在 HomeView）、`App/RootView.swift:36`（`ErrorBanner` 挂在 NavigationStack 上）
- 问题：在场景 sheet 里点选候选（`SceneSheet.swift:143-150` → `applySceneChange` → `showUndo`）时，吐司出现在 sheet 下面的首页，4 秒后消失，用户永远看不到“撤销”；资料库 / 最近连接 / 今日 / 指令里的引擎错误同样不可见。
- 建议：吐司与错误横幅改为窗口级覆盖（独立 `UIWindow` 叠在 sheet 之上，或在 `SheetHost` 内也挂同一个 `.zToast($model.toast)` 与 `ErrorBanner`）；或场景候选点选后先 `dismissSheet()` 再出吐司（原型 06 的做法更接近后者）。

**H-P1-2 首页场景行没有大字体堆叠布局（原型 19，xl.png）**
- `Home/SceneRow.swift:34-62`（恒为 HStack）、`:96-99`（节点名 `lineLimit(1)`）
- 问题：原型 xl 下每行改为上下堆叠：名称 → 可用数 → [SG] 新加坡 02 → 锁定说明。现在 AX 尺寸下左右两栏挤在一行，节点名截断、锁定说明被裁。`ZGroupCard` 已实现这套堆叠（`ZGroupCard.swift:57-59`），但 SceneRow 没用它。
- 建议：SceneRow 直接用 `ZGroupCard` 渲染（横滑、确认卡逻辑留在 SceneRow），或照搬 `dynamicTypeSize >= .xxLarge` 时的 `VStackLayout`。注意原型在 xl（非 AX）就开始堆叠。

**H-P1-3 场景行没有按压反馈**
- `Home/SceneRow.swift:45-51`
- 问题：可横滑的行由 `HorizontalPanOverlay` 的 `UITapGestureRecognizer` 接管点按，没有任何按下态；原型 `.row:active{background:rgba(255,255,255,.025)}`。首页最主要的可点区域点下去毫无反应，要等 sheet 弹出才知道点中了。
- 建议：在 overlay 的 `UILongPressGestureRecognizer(minimumPressDuration: 0)`（与 pan 同时识别，pan 开始时取消）回调里切换 `@State pressed`，背景用 `screenPressed`；不可横滑行用 `ZRowButtonStyle`。

**H-P1-4 首页曲线 120Hz 常驻、每帧在主线程分配，且在 sheet 下继续跑**
- `Home/TrafficChart.swift:30-37`
- 问题：`TimelineView(.animation(minimumInterval: nil))` 在 ProMotion 上 120fps；每帧 `ring.suffix(120)`（新数组）→ 两次 `map` 求 min/max → `Array(window.suffix(62))`，再重建两条 Path 与渐变。数据 1Hz 才变一次。首页被场景/资料库/今日 sheet 盖住时视图仍在层级中，时间线不会暂停。VPN App 首页常被长时间停留，耗电明显。
- 建议：① `minimumInterval: 1/60`（滚动插值肉眼足够）；② lo/hi 与可见点快照在 `TrafficStore.push` 时算好（1Hz），帧内只做插值；③ 用 `@Environment(\.isPresented)`/scenePhase 或 HomeView 传入 `isCovered`（`model.sheet != nil || model.isCommandPresented`）把 `paused` 置真；④ 用 `.drawingGroup()` 或把曲线移到 `Canvas(rendersAsynchronously: true)`。

**H-P1-5 原型 11“服务不可用”无法表达**
- `Home/SceneRow.swift:76-90`；`ZephyrKit/Models.swift:130-152`（`Scene` 无按服务的健康状态）
- 问题：zero.png 要求左侧红字“Claude 不可用”、右侧“GPT、Gemini 正常”；现在只有 `available <= 0` 时的“暂无可用节点”。这是首页三种状态变体之一（README 页面清单 10/11/12）。
- 建议：请 A 在契约里给 `Scene` 加 `services: [ServiceHealth{name, ok}]`（或 `unavailableServices: [String]`）；SceneRow 按原型渲染并把 a11y 文案同步。合入前至少在 NOTES 标为缺口。

**H-P1-6 指令输入框“透明 TextField + 镜像文字”在中文输入与长文本下失真**
- `Command/CommandView.swift:95-110, 124-137`
- 问题：① 镜像是 `lineLimit(1)` 的 Text，超出宽度时末尾省略号截断，而真实 TextField 横向滚动，光标与可见文字错位；② 拼音输入时系统 marked text 的样式随前景一起透明，镜像只显示原始字母，且 80ms 后就拿拼音片段去请求 `commandSuggestions`；③ 镜像与 TextField 的基线/字距只靠同一 font 对齐，Dynamic Type 下易漂移。
- 建议：用 `UIViewRepresentable` 包 `UITextField`，直接给 `attributedText` 加下划线属性（`.underlineStyle` + `.underlineColor`），`markedTextRange != nil` 时跳过 tokenize 与请求；或至少在溢出时让镜像跟随 TextField 的滚动偏移、composing 期间暂停解析。

**H-P1-7 今日卡片打开时在主线程同步渲染 3× 大图并编码 PNG**
- `Activity/TodayCardView.swift:57, 110-124`；`Activity/WindArt.swift:36-56, 84-88`
- 问题：`.task(id:)` 首次运行就 `ImageRenderer` 渲染 1038×1500（288 条流线 × 最多 150 步三角函数 + 渐变描边）并 `pngData()`，都在主线程，正好与 sheet 弹出动画重叠，必然掉帧；`refreshUsage()` 返回后 `usage` 变化又整套重来一次。卡片本体 30fps 动画同时在算同样的 288 条线。
- 建议：导出改为“点分享/存储时再渲染”，或放到 `Task.detached`（用纯 CoreGraphics 绘制 WindArt，不依赖 SwiftUI 渲染器），`pngData` 同样离开主线程；`RenderKey` 去抖（等 usage 稳定）。流线线数在页面内可降到 ~150，导出时用全量。

**H-P1-8 切换确认卡把整页 VoiceOver 焦点锁死**
- `Home/SceneChangeConfirm.swift:49`（`.accessibilityAddTraits(.isModal)`）
- 问题：内联卡片标 `isModal` 后，VoiceOver 只能在卡内移动，首页其余内容（含指令栏、开关）全部不可达，直到用户确认或取消；而这张卡并没有遮罩，视觉上不是模态。
- 建议：去掉 `.isModal`；出现时 `AccessibilityNotification.LayoutChanged(focus)` 把焦点移到卡片标题即可。

**H-P1-9 轨迹页“本次连接 / 始终应用”以禁用 UI 上线**
- `Activity/TraceOverrideSection.swift:43-64`
- 问题：整块 55% 透明、不可点，配一句“此版本暂不支持”。对标一线 App，这是死路 UI：看得见、点不动。
- 建议：契约未就绪前整段不显示（原型 09 的覆写放到契约到位后的版本）；或替换为一行“在规则页添加覆写 ›”跳转。

### P2
- **H-P2-1** `Home/HomeHero.swift:100-101,126`：模式与时长应为 14px（`.sub` font-size 14），模式字重常规（现在 13 medium）；`:28` 间距 16 → 14；`HomeView.swift:25` hero 上边距 12 → 18（`.hero` padding-top 18）。
- **H-P2-2** `Home/HomeHero.swift:123`：时长用 `TimelineView(.periodic)` 每秒重算一次 body；改 `Text(Date(timeIntervalSince1970: since/1000), style: .timer)`，格式同为 “2:14:07”，零 body 重算、锁屏/后台恢复也准。
- **H-P2-3** `Home/SceneRow.swift:96-97`：右侧节点名 17 → 15（`.ex` font-size 15）；`:106` 锁图标色走 P0-2 的 amber（原型 opacity .85）。
- **H-P2-4** `Home/ScenesSection.swift:35` + `SceneRowParts.swift:36-56`：后一行之前的 `ZDivider` 绘制在上一行的 coach 提示之上，细线会穿过“左右滑动以切换地区”；原型提示用 `--s1` 底盖住分隔线。给 coach 所在行 `.zIndex(1)` 或把 coach 放到 ZCard 的 overlay 里按行位置定位。
- **H-P2-5** `Home/SceneChangeConfirm.swift:24,40-41`：标题 16 → 14（`.cf .h`），内边距 12 → 14，底色 `ZTrackFill().opacity(0.6)` → `screenS3`（scrub.png 的卡片是实色 s3）。
- **H-P2-6** `Home/SubscriptionsSection.swift:72,82,88`：名称 16 → 17（`.row .n`），剩余量 16 → 17，到期 12 → 13（`.row .m`）；`ZFormat.expiry`（`ZephyrKit/Format.swift:88`）近 7 天显示“11月9日到期”，原型首页是“周一到期”（global.png），订阅页是“11月9日到期”（subs.png），首页应用星期。
- **H-P2-7** `AppModel.swift:77-81`：`scenesTestedText` 的“2 小时前检测”只在别的状态变化时才更新；用 `TimelineView(.everyMinute)` 包一下这一个 Text。
- **H-P2-8** `Home/HomeHeader.swift:20`：设置入口用 `sun.max`。原型就是这个图形，但 SF 里 `sun.max` 的语义是亮度/外观，VoiceOver 标签是“设置”而图形像亮度，建议与设计确认是否换 `gearshape`（或保留但在 NOTES 注明是品牌决定）。
- **H-P2-9** `Scene/SceneSheet.swift:48-52`：分段控件 `.constant` + `.disabled(true)`，外观可点但点不动；契约无 `setSceneSource` 前改为只读文案“来源：Zephyr 优选”。`:154`、`:162-164` 漏斗只有 3 级、文案“全部候选 / 全部可访问”与原型（全部 / 延迟低于 300 ms / 可访问 GPT / 可访问 GPT、Claude 和 Gemini）不一致，lede 也不是“检测自 2 个订阅中的 512 个节点”——同属契约缺口，记入 NOTES。
- **H-P2-10** `Scene/SceneCandidateRow.swift:17-19,35-36`：未选中节点名用 t2，原型全部 t1（scene.png）；字号 16 → 15，行内边距 12/16 → 13/14（`.li`）。
- **H-P2-11** `Activity/TodayCardView.swift:35-37`：原型 14（today.png）是全屏纯黑页 + 右上 ✕，没有抓手与 sheet 底；改 `fullScreenCover`（RootView.SheetHost `.today`），背景 `screenBg`。
- **H-P2-12** `Activity/TraceView.swift:163`：流光用 `TimelineView(.animation)` 120Hz 只为画 1px 线；改 `.animation(minimumInterval: 1/30)`，或用 `repeatForever` 的 offset 动画交给 Core Animation。
- **H-P2-13** `Activity/ActivitySheet.swift:25,32,59,69`：`hosts` 是计算属性，每次 body 至少聚合 3 次（列表、isEmpty、TraceView 参数），活动连接流每次推送都触发；在 `.task` 收到列表时算一次存 `@State`。`:60-65` 首帧前把空态文案 redacted 当骨架，改为 3–4 行行骨架。
- **H-P2-14** `Activity/ActivitySheet.swift:77-81`：长按“关闭 n 个连接”无确认、无结果反馈；关闭后给吐司（并可撤销则撤销）。
- **H-P2-15** `Activity/TraceView.swift:43`：域名 30pt light；trace.png 约 36pt 级别，按原型核对（css 未单列，按截图量 ~34–36）。
- **H-P2-16** `Command/CommandResults.swift:84-90`：token 卡片标签 12 → 10.5、值 16 → 15、内边距 12/8 → 12/8 ✓，底色 → `screenS2`，缺原型 `pcIn` 依次淡入（每张 +40ms）。`:57` 建议列表 `id: \.offset` 让增删动画错位，改用建议自身 id（title+kind+payload）。
- **H-P2-17** `Command/CommandView.swift:42-48`：`onAppear` 里立刻 `focused = true` 在 overlay 首帧经常不生效；改 `.defaultFocus` 或 `Task { await Task.yield(); focused = true }`。指令层与底部胶囊之间没有几何过渡，可用 `matchedGeometryEffect` 让胶囊“长成”输入框（Spotlight 式），这是对标顶级 App 的关键一笔。
- **H-P2-18** `Command/CommandModel.swift:64,79-81`：每次输入都可能对每个场景 `sceneCandidates`，失败会写 `lastError` 弹横幅；指令层内的预取失败应静默。
- **H-P2-19** `App/AppModel+Streams.swift:85`：`engine.recentTraffic(seconds:)` 是同步方法，在 MainActor Task 里调用；真实引擎走 FFI 时会阻塞主线程，改 `await Task.detached { … }.value`。
- **H-P2-20** `App/RateRing.swift` + `TrafficStore.swift:33`：`ring` 是值类型存于 `@Observable`，每次 `append` 经 get/set 触发一次 300 元素 CoW 拷贝（1Hz，影响小），可改为引用类型缓冲 + 手动 `withMutation`。
- **H-P2-21** `App/AppModel+Navigation.swift:52-56`：任何 App / 网页都能通过 `zephyr://disconnect`、`zephyr://mode/global` 无提示地断开或切模式；对 VPN 属隐私风险，外部来源（非小组件/快捷指令）的连接类深链应先确认。
- **H-P2-22** `App/AppServices.swift:143-151`（App 层，归 X，但影响 Intent 体验）：`ModelConnectionControl` 用 `model.lastError` 判断成败，会把之前残留的错误当成本次失败抛出；`connect()/disconnect()` 应直接 throw。

---

## 三、Library + Nodes + Rules + Subs + Settings + Onboarding（L）

### P1
**L-P1-1 资料库进入的页面返回到首页，而不是资料库**
- `App/RouteDestination.swift:36-44`、`App/AppModel+Navigation.swift:17-21`
- 问题：原型节点/规则/订阅/设置页左上是“‹ 资料库”（nodes.png、rules.png、subs.png、settings.png）。现在 `push` 会先关掉资料库 sheet，返回后落在首页；且首页没有 `navigationTitle`（`HomeView.swift:45` 隐藏了导航栏），系统返回按钮显示“返回”。
- 建议：记录来源（`Route` 增加 `from: .library`），在 NavigationStack 首页设置隐藏的 `navigationTitle("资料库")` 供返回按钮使用，并在 pop 回根时重新 `present(.library)`；或把资料库改为 push 的第一层页面（与原型返回语义一致）。

**L-P1-2 资料库统计卡布局与原型不符**
- `Library/LibraryStatCard.swift:16-21`；`ZBigNumber.swift:48-52`
- 问题：原型 `.lc` 固定高 110、数字在顶、说明在底（space-between），说明 14px t2；现在数字下 4pt 紧跟 12px t3 caption，卡片只有 ~70pt 高，lib.png 的 2×2 方块感没有了。
- 建议：卡片内 `VStack { number; Spacer(); Text(caption).zType(.footnote 14) t2 }.frame(minHeight: 110)`（AX 尺寸下取 max(110, 内容高)）；底色 `screenS2`、圆角 20、边框 `screenHl`。

**L-P1-3 节点搜索每个按键都打一次全量查询**
- `Nodes/NodesView.swift:47`、`Nodes/NodesModel.swift:57-72`
- 问题：`onChange(of: query)` 直接 `runQuery()`，没有去抖；`queryNodes` 面对 1e8 级索引（真实引擎走 FFI），拼音输入时每个字母都会触发，旧请求只是结果被丢弃，底层计算并未取消。
- 建议：与指令层一致加 120–150ms 去抖（`Task.sleep` 后检查 `Task.isCancelled`），composition 期间不查；chips 点选（`select(chip:)`）可绕过去抖立即查。

**L-P1-4 规则页“+ 添加覆写”是死路**
- `Rules/RuleAddSheet.swift:36-38`、`Rules/RulesView.swift:40-49`
- 问题：完整的输入 UI，但“添加”永远禁用，只在说明里告诉用户去电脑上加；且该 sheet 用系统样式（没走 `zSheetPresentation`），与其它 sheet 不一致。
- 建议：契约无写覆写接口前隐藏右上角“+”；若必须保留入口，改为一张说明卡（`zSheetPresentation(.medium)`），不要放可编辑但不可提交的表单。

### P2
- **L-P2-1** [已修] `Onboarding/OnboardingView.swift:171`：标题用 `zDisplay(.title)` = 44 Thin；原型 `.ob h1` 是 34 Light、行高 1.18（ob1.png / ob2.png）。改 34 / `.light`，`lineSpacing` 补到 1.18。
- **L-P2-2** `Onboarding/OnboardingView.swift:83`：“1 / 2” 距标志 60pt，原型 `.step-n` margin-top 28；整体垂直节奏偏松。
- **L-P2-3** `Library/LibrarySheet.swift:68-80`：“受信任的 Wi‑Fi”“本地代理端口”都跳到设置首页，应直达 `TrustedWifiView` / `LocalProxyView`（给 `Route` 加子页）；文案原型为“连上这些 Wi‑Fi 时自动断开 / 家里”“本地代理端口 / 关”，现为“受信任的 Wi‑Fi”“7890”（端口开关缺字段，记 NOTES）。
- **L-P2-4** `App/RouteDestination.swift:42-43`：资料库“场景”卡片在 sheet 已呈现时把 `sheet` 换成 `.scene`，SwiftUI 会先关后开，偶发闪动；先 `dismissSheet()`，在 `onDismiss` 里再呈现。
- **L-P2-5** 生产代码 `import ZephyrMock`：`NodesView.swift:9`、`RulesView.swift:7`、`LibrarySheet.swift:10`、`SettingsView.swift:8`、`SubscriptionsView.swift:13`、`OnboardingView.swift:10`、`TrustedWifiView.swift:8` 只为预览；用 `#if DEBUG` 包住，并让 `ZephyrFeatures` 不在 Release 链接 Mock。
- **L-P2-6** `Nodes/NodeListStyle.swift:108` 用 `ms > 200` 判慢，`SceneCandidateRow.swift:45` 与 token（`ZTokens.LatencyThreshold`）用 `>= 200`；统一走 `ZTokens.LatencyThreshold.color`。
- **L-P2-7** `Nodes/NodeListView.swift:149` 与 `NodeCell.swift:131`：`traitCollectionDidChange` 在 iOS 17 已弃用，改 `registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self])`。
- **L-P2-8** `Nodes/NodeRowStore.swift:118-125`：页请求失败后只从 `inFlight` 移除，行永久停在骨架直到再次滚动；加有限次重试或在 footer 显示“载入失败 · 重试”。
- **L-P2-9** `Nodes/RegionChips.swift:37,52`：chip 触控高 38（< 44）；每个 chip 各挂 `.sensoryFeedback(trigger: on)`，切换时新旧两个 chip 同时触发两次触感，改为在父视图对 `selected` 挂一次。`:27` 选 chip 等于把地区码写进搜索框做文本搜索（“US”可能匹配名称），应走契约的地区过滤或至少用 `region:US` 语法。
- **L-P2-10** `Settings/SettingsView.swift:43`：`.disabled(store.settings == nil)` 挂在 ScrollView 上，首帧前连滚动都禁用；只禁用各分组。
- **L-P2-11** 错误呈现不统一：首页顶部横幅（RootView），订阅/设置用底部吐司（`SubscriptionsModel.swift:201-209`、`SettingsView.swift:46-51`），节点页 `failed` 状态（`NodesModel.swift:69`）没有任何 UI。统一成一种（建议吐司 + 可重试动作），并给节点页加错误态。
- **L-P2-12** `Subscriptions/SubscriptionsView.swift:33,37`：List section header 里放 `ZSectionHeader`，insetGrouped 会再叠一层系统 header 内边距；核对 subs.png 中“流量 / 本月”与卡片左缘对齐（原型 22pt）。
- **L-P2-13** `Rules/RulesView.swift:51`：`onChange(of: input)` 每键 testRule，引擎很快问题不大，但同 L-P1-3 应在 composition 期间跳过。
- **L-P2-14** `Settings/SettingsView.swift`：原型设置页有“应用图标 · 深色”（settings.png 外观分组），未实现也未在 NOTES 中注明。

---

## 四、Widgets（X）

### P1
**W-P1-1 实时活动过期后仍显示“实时”速率**
- `Widgets/ZephyrLiveActivity.swift:10-14`、`Views/LiveActivityLockView.swift`、`Views/IslandViews.swift`；`App/LiveActivityController.swift:168,219,234`（已设 `staleDate` 2 分钟）
- 问题：App 进后台后流量订阅被取消（`AppModel+Streams.swift:81`），实时活动不再更新；系统 2 分钟后把它标记为 stale，但视图没有读 `context.isStale`，锁屏和灵动岛继续显示最后一次的“2.8 MB/s ↓”。锁屏正是用户最常看它的地方，对 VPN App 是信任问题。
- 建议：`ActivityConfiguration` 闭包里把 `context.isStale` 传进视图：速率改为“—”或降为 t3 并加“已暂停更新”；计时器（`Text(.timer)`）照常走。长期方案：PacketTunnel 侧经 APNs 推送更新（NOTES-X 已提）或只展示不随秒变化的信息（模式、场景、时长）。

**W-P1-2 主屏小组件把瞬时速率当主数字，但最长 15 分钟才刷新**
- `Views/StatusSmallView.swift:32-43`、`StatusMediumView.swift`；`SharedTimelineProvider.swift:17,35-40`；`App/SharedStatePublisher.swift:3-4`（速率只写盘不 reload）
- 问题：小组件大字“2.8 MB/s”是最后一次时间线生成时的瞬时值，可能是十几分钟前甚至已断开前的数据（断开会 reload，但长时间连接中不会）。
- 建议：小组件主数字换成不随秒变化的信息（“已连接 · 规则 · 东京 03”或今日用量），速率若保留需配 `Text(entry.date, style: .relative)`“x 分钟前”；或仅在 `widgetRenderingMode`/StandBy 下显示。原型 hs.png 画了速率，此处与设计确认后在 NOTES 说明偏离理由。

### P2
- **W-P2-1** `Views/LiveActivityLockView.swift:85-88`：场景徽标行文字 16（body）；原型 `.la .sc` 12.5px，三个场景在窄屏上会被压缩/截断；改 `.caption`。
- **W-P2-2** `Views/IslandViews.swift:22-24`：紧凑态尾部用 17 semibold 等宽，原型是小号“2.8 ↓”；系统建议紧凑区 ≤ 15pt，改 `.footnote/.subheadline`，并限定宽度避免把岛撑宽。
- **W-P2-3** `Views/RegionBadge.swift:12-20`：徽标 12pt / 圆角 4 / 描边 borderStrong，与 App 内 `ZFlag`（10.5pt、圆角 5、hl2）不一致；对齐到同一规格（扩展里可复制常量，不必依赖 ZFlag 签名）。
- **W-P2-4** `SharedTimelineProvider.swift:48-50`、`ZephyrLiveActivity.swift:12`：背景 `bgElevated` #18181B@0.97；原型锁屏卡片 rgba(18,18,22,.62)+模糊、主屏小组件为深色玻璃。改为 P0-2 的 `screenGlass`（活动卡）/ `screenS1`（主屏），浅色跟随。
- **W-P2-5** `ZephyrConnectionControl.swift:18`：控制中心开关固定蓝色，未跟随用户强调色（`SharedState.accent` 可读）。
- **W-P2-6** `Views/PowerButton.swift:15-16`：原型是 36pt 白色圆 + 黑色图标（hs.png），现在 44pt 实心；视觉缩到 36，触控区靠 `contentShape` 扩到 44。
- **W-P2-7** `Views/ScenesMediumView.swift:42`：场景名列宽 44pt 写死（虽有 ScaledMetric），自定义场景名较长时截断；改为按最长名测量或 `fixedSize`。

---

## 最重要的 10 条（按修复优先级）

1. **P0-1** 引导页未接入，首启直接进首页（`OnboardingView` 仅快照引用）。
2. **P0-2** 设计系统未用 `screen.*` 色板：全局 Tailwind 语义色、sheet 内卡片比底色暗（层级反转）、吐司/轨道/玻璃色值都不对。
3. **H-P1-1** 撤销吐司与错误横幅被 sheet 盖住，场景 sheet 里换节点后永远看不到“撤销”。
4. **H-P1-2 / H-P1-3** 首页场景行：大字体不堆叠（原型 19）、点下去没有任何按压反馈（SceneRow 未复用 ZGroupCard）。
5. **H-P1-4** 首页曲线 120Hz 常驻 + 每帧主线程分配，被 sheet 盖住也不停。
6. **W-P1-1 / W-P1-2** 实时活动过期仍显示速率；主屏小组件主数字是最长 15 分钟前的瞬时速率。
7. **H-P1-6** 指令输入框镜像方案：长文本光标错位、拼音输入期间失真并按拼音发请求。
8. **H-P1-7** 今日卡片打开时主线程同步 ImageRenderer 3× + PNG 编码，弹出动画必卡。
9. **L-P1-1** 从资料库进入的页面返回到首页，返回按钮显示“返回”而非“资料库”。
10. **D-P1-1 / D-P1-2** 触感滥用（每次按下都震）；`ZSettingsRow` 合并无障碍元素导致强调色无法用 VoiceOver 选择。

## 未能确认 / 需要后续验证
- 未在 Xcode 编译，**没有发现确定的编译错误**；静态看到的签名、`@MainActor`、Sendable 用法均能对上。风险点只有 D-P2-10（macOS 平台 + UIKit）。
- 性能条目（H-P1-4、H-P1-7、WindArt）需用 Instruments（Time Profiler + Animation Hitches）在真机复核量级。
- SwiftUI `TextField` 在拼音 marked text 期间是否回写绑定，不同 iOS 小版本行为不一，H-P1-6 第 ② 点需真机验证；第 ① 点（溢出错位）可确定。
- 原型 trace 页域名字号 CSS 未单列，H-P2-15 按截图估算。

# Zephyr iOS 架构（B · Agent-iOS）

验收标准 = `design/prototype/`（打开 index.html，25 个章节；截图在 `design/prototype/shots/`）+ `design/notes/*.md`。
**原型的信息架构以原型为准**：不是 4 个 Tab，而是「单一首页 + 资料库 sheet + 指令搜索栏」。

## 目录
```
apps/ios/
  project.yml                 XcodeGen 工程（xcodegen generate → Zephyr.xcodeproj，不入库）
  Packages/ZephyrKit/         本地 SPM 包，全部可复用代码
    Sources/ZephyrKit/        纯 Swift：ZephyrEngine 协议、Models、Format。Linux 可编译
    Sources/ZephyrMock/       纯 Swift：MockEngine（移植 pages.js 的确定性算法）。Linux 可编译
    Sources/ZephyrDesign/     SwiftUI：Tokens（生成）+ Z* 组件
    Sources/ZephyrFeatures/   SwiftUI：AppModel + 全部页面
    Tests/                    XCTest；ZephyrKitTests / ZephyrMockTests 在 Linux 也跑
  App/                        App target（极薄：@main、依赖注入、深链、App Intents）
  PacketTunnel/               NEPacketTunnelProvider（mihomo 以 C 静态库嵌入，禁止 Process()）
  Widgets/                    WidgetKit：主屏小组件、锁屏小组件、实时活动（ActivityKit）、控制中心开关（iOS 18 ControlWidget）
  Shared/                     App 与扩展共享：App Group 存储、Darwin 通知、Live Activity attributes
  SnapshotTests/              swift-snapshot-testing：每个组件/页面 × 深浅 × 4 强调色 × 大字体
```

## 页面清单（对应原型章节）
| 原型 | iOS 视图 | 说明 |
|---|---|---|
| 01–03 第一次打开/选择默认/连接 | `Onboarding/` | 添加订阅（粘贴/扫码/从电脑导入/文件）→ 简单/优选 → 连接（VPN 授权）|
| 04 首页 | `Home/HomeView` | 状态大字 + 开关、模式菜单、连接时长、速率大数字 + 曲线、场景卡、订阅卡、底部指令栏 + 资料库按钮 |
| 05 切换地区 | 场景卡左右滑 | 横向分页切换地区，触感反馈 |
| 06 场景 | `Scene/SceneSheet` | 大数字、订阅分组/Zephyr 优选分段、漏斗、候选列表 |
| 07 指令 | `Command/CommandView` | 搜索栏展开为全屏，解析成 token，预览并“应用” |
| 08 最近连接 / 09 连接轨迹 | `Connections/` | sheet 列表 → 轨迹（规则→场景→节点→出口）+ 本次覆写分段 + 始终应用 |
| 10 检测中 / 11 服务不可用 / 12 全局模式 | 首页状态变体 | 场景卡进度、警告色、全局模式卡 |
| 13 资料库 | `Library/LibrarySheet` | 2×2 统计 + 小组件与控制中心 / Wi‑Fi / 本地端口 / 设置 |
| 14 今日 | `Today/TodayCardView` | 生成式纹理卡片（夜/晨/雾三种），分享、存储图像 |
| 15 锁屏 / 16 小组件 / 17 Android | Widgets 扩展 | 实时活动 + 灵动岛；小/中号小组件；控制中心开关 |
| 18 浅色 / 19 大字体 | 全局 | 所有视图必须支持 |
| 20/21 节点、搜索 | `Nodes/NodesView` | UICollectionView 虚拟列表（固定行高 52/66pt，自管偏移，支持 1e8 行）、置顶头、右侧地区索引条 + 气泡、底部“n / total · 已检测 x”，停止滚动 400ms 测可见行 |
| 22/23 规则 | `Rules/RulesView` | 总数、测试框、命中链、7 层匹配顺序 |
| 24 订阅 | `Subscriptions/` | 总数、最近更新 diff、流量卡、更新设置 |
| 25 设置 | `Settings/` | 连接 / 检测 / 存储 / 外观 分组 |

## 约定
- iOS 17 起；状态用 Observation（`@Observable`）。不引入第三方 UI 库；测试用 swift-snapshot-testing。
- 视图只依赖 `AppModel`/各页 `Model`，模型只依赖 `any ZephyrEngine`。Preview 和快照测试注入 `MockEngine(seed:)`，时间固定为原型的 9:41。
- 每个文件一个组件，页面文件 ≤ 300 行；颜色/字号/间距/动效只从 `ZTokens` 取，禁止魔数。
- 大数字：`.font(ZFont.display)`（细字重 + 等宽数字 `monospacedDigit()`）。
- 文案中文，放 `Localizable.xcstrings`（后续加英文）。
- 性能：节点列表 1e8 行 60fps（120Hz ProMotion 设备 120fps），冷启动 < 1s，首页曲线用 Canvas 绘制、TimelineView 驱动，不触发整页重绘。
- 无障碍：所有可交互元素有 label；大数字给出朗读文本；Reduce Motion 下禁用 spring 光晕。

## 并行分工（iOS 内部，subagent）
- K：ZephyrKit/ZephyrMock + Linux 单测
- D：ZephyrDesign（tokens 生成 + Z* 组件）
- H：首页 / 场景 / 指令 / 连接记录 / 今日
- L：资料库 / 节点 / 规则 / 订阅 / 设置 / 引导
- X：project.yml / App / PacketTunnel / Widgets / Shared / 快照测试 / CI 脚本

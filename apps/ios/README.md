# Zephyr iOS

Mihomo / Clash Meta 代理客户端的 iOS App：SwiftUI + Observation，iOS 17 起。
架构、页面清单与约定见 [ARCHITECTURE.md](ARCHITECTURE.md)；引擎接口以仓库根的 `contract/zephyr-engine.md` 为准。

## 环境

| 工具 | 版本 |
|---|---|
| Xcode | 16.0+（CI：`macos-15` 默认 Xcode） |
| XcodeGen | 2.38.0+（`brew install xcodegen`） |
| 模拟器 | iPhone 16（快照参考图按 393×852 录制） |

工程文件 `Zephyr.xcodeproj` **不入库**，由 `project.yml` 生成；三个 target 的 `Info.plist` 也是生成的（改键请改 `project.yml` 的 `info.properties`）。

## 本地构建

```sh
cd apps/ios
scripts/bootstrap.sh            # 装 XcodeGen（如缺）→ 初始化子模块 → 生成工程 → 打开 Xcode
scripts/bootstrap.sh --no-open  # 只生成（终端 / CI）

# 或手动：
xcodegen generate
open Zephyr.xcodeproj
```

改了 `project.yml`、或新增 / 删除了源文件之后，重新 `xcodegen generate`。

命令行构建并跑全部测试（与 CI 相同）：

```sh
xcodebuild -project Zephyr.xcodeproj -scheme Zephyr \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -resultBundlePath build/Test.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

scheme `Zephyr` 的 test action 包含：`ZephyrTests`（Shared/Core 与 PacketTunnel 纯逻辑）、`ZephyrSnapshotTests`（快照）、本地包的 `ZephyrKitTests` / `ZephyrMockTests`。

`ZephyrKit` / `ZephyrMock` 是纯 Swift，Linux 上也能 `swift test`（`Packages/ZephyrKit`）；SwiftUI 目标只能在 macOS 上编译。

### Targets

| Target | 内容 |
|---|---|
| `Zephyr` | App（极薄：`@main`、引擎注入、深链、App Intents、实时活动驱动） |
| `PacketTunnel` | `NEPacketTunnelProvider`，mihomo 以静态库嵌入；未链接核心时为桩实现，拒绝启动隧道 |
| `ZephyrWidgets` | 主屏 / 锁屏小组件、实时活动 + 灵动岛、iOS 18 控制中心开关 |
| `ZephyrTests` | 不托管的单测：SharedStore、PendingCommand、TunnelMessage、隧道网络设置、MihomoBridge 桩、MappedFile |
| `ZephyrSnapshotTests` | 页面 / 组件 / 小组件 / 实时活动 × 深浅 × AX5 × 强调色 |

### 签名

默认 `DEVELOPMENT_TEAM` 为空、`CODE_SIGN_STYLE: Automatic`：模拟器和 CI（`CODE_SIGNING_ALLOWED=NO`）不需要签名。
真机运行需要在 Xcode 里给三个 target 选自己的 Team，并确保 App Group `group.app.zephyr.mobile` 与 Network Extension（Packet Tunnel）能力可用。
无签名时 entitlements 不生效，App Group 容器回退到本进程的 `Application Support/ZephyrShared`（见 `Shared/Core/AppGroup.swift`）。

## 启动参数

在 Xcode：Product → Scheme → Edit Scheme → Run → Arguments；或 `xcrun simctl launch booted app.zephyr.mobile -ZephyrEngine mock -ZephyrClock frozen941`。
参数经 `UserDefaults` 读取（`App/LaunchEnvironment.swift`）：

| 参数 | 取值 | 作用 |
|---|---|---|
| `-ZephyrEngine` | `mock` \| `core` | 强制引擎。Debug / 模拟器默认 `mock`；`core` 需要 `ZephyrCore` 模块 + Release 的 `ZEPHYR_CORE_ENGINE` 条件，不可用时自动回落 `mock` |
| `-ZephyrClock` | `frozen941` | 时钟冻结在原型的 2026-11-06 9:41（+08:00），连接时长固定 2:14:07；录屏 / 截图用 |
| `-ZephyrSeed` | 整数 | MockEngine 种子（只影响流量抖动与订阅 diff） |

scheme 的 Run 默认带 `-ZephyrEngine mock`。在测试进程里（`XCTestConfigurationFilePath` 存在）总是 `mock` + 冻结时钟。

## 快照测试

基于 [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)，断言统一走 `SnapshotTests/Support/ZSnapshot.swift` 的 `zAssertSnapshot` / `zAssertSnapshots`：

- **渲染**：`UIHostingController` 放进 iPhone 16 尺寸（393×852，安全区 59 / 34）的 `UIWindow`，等 `.task` 和引擎数据落定（`settle`）再出图，2x。
- **变体**：`ZSnapshotVariant.standard` = 深色 / 浅色 / 深色 AX5；`standardPlusAccent(_:)` 再加一个强调色抽样（各用例轮流抽 green / orange / pink）。
- **数据**：`AppModel.preview(frozen: true)` / `MockEngine(clock: .frozen941)`；小组件用 `SharedState.prototype(now:)`，时间固定 9:41。
- **参考图**：`SnapshotTests/__Snapshots__/<测试文件名>/<测试名>.<名字>-<变体>.png`。

### 录制模式

由环境变量 `ZEPHYR_SNAPSHOT_RECORD`（优先）或 `SNAPSHOT_RECORD` 控制（scheme 的 test action 固定 `SNAPSHOT_RECORD=missing`）：

| 值 | 行为 |
|---|---|
| `missing`（默认） | 缺参考图时**录制且不判失败**（图附在 xcresult 里）；有参考图则断言 |
| `all` | 全部重录、不失败（有意改了视觉之后用） |
| `never` | 缺参考图直接失败（参考图入库后可在 CI 打开，防止漏录） |

```sh
# 首次录制 / 补录缺失的参考图
xcodebuild … test -only-testing:ZephyrSnapshotTests

# 改了视觉后全部重录（xcodebuild 把 TEST_RUNNER_ 前缀的变量去掉前缀后传给测试进程）
TEST_RUNNER_ZEPHYR_SNAPSHOT_RECORD=all xcodebuild … test -only-testing:ZephyrSnapshotTests

# 只重录一个用例
TEST_RUNNER_ZEPHYR_SNAPSHOT_RECORD=all xcodebuild … test \
  -only-testing:ZephyrSnapshotTests/WidgetSnapshotTests/testStatusSmall
```

在 Xcode 里则改 scheme → Test → Arguments → Environment Variables 的 `SNAPSHOT_RECORD`。
录完检查 `git status` 里新增 / 变化的 PNG，确认无误后一并提交。参考图务必在 **iPhone 16 模拟器 + 同一大版本 Xcode** 上录制，否则字体渲染差异会让断言失败（容差：99% 像素、98% 感知精度）。

断言失败时，库会把实际图写到 `$SNAPSHOT_ARTIFACTS`（默认系统临时目录），并在 xcresult 里附上 reference / failure / difference 三张图。

### 新增用例

```swift
@MainActor
final class MyViewSnapshotTests: XCTestCase {
    func testMyView() async {
        await zAssertSnapshots(named: "my-view", variants: ZSnapshotVariant.standardPlusAccent(.green)) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)   // 每个变体一个新引擎
            return NavigationStack { MyView(engine: engine) }
        }
    }
}
```

名字只用小写字母、数字和 `-`（会进文件名）。组件陈列用 `layout: .fitWidth(393)`，小组件用 `.fixed(size)`。

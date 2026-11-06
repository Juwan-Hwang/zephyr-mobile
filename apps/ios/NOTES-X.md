# NOTES-X（X2 · 工程 / 测试 / 扩展）

分支 `agent/ios/pages`（基于 main `a8a8732`）。只改了 `apps/ios/` 下 X 的目录，未动 `Packages/`。

## 本轮做了什么

### 快照测试（`SnapshotTests/`）
- `Support/ZSnapshot.swift`：`zAssertSnapshot` / `zAssertSnapshots`。自托管渲染（UIWindow 393×852 + 安全区 59/34，等 `.task` 落定后 `layer.render`，2x），
  缺参考图时录制且不失败、有图时用 `verifySnapshot` 断言（precision 0.99 / perceptual 0.98）。`SNAPSHOT_RECORD=missing|all|never`。
  参考图集中在 `SnapshotTests/__Snapshots__/<测试文件名>/`（已放 `.gitkeep`）。
- `Support/SnapshotFixtures.swift`：9:41 冻结时间、冻结 MockEngine 工厂（可把强调色写进引擎设置）、小组件 SharedState 变体（已连接 / 未连接 / 失败 / 全局 / 空 / 边界场景）。
- `Cases/`：
  - `HomeSnapshotTests`：HomeView 已连接 / 未连接 / 全局模式 × (深 / 浅 / AX5 + 强调色)；RootView 已连接（深 / 浅 / 粉）与未连接。
  - `LibraryPagesSnapshotTests`：NodesView（全部 / 搜索“东京 IPLC” / 无结果）、RulesView（默认 / 被拦截域名）。
  - `ActivitySnapshotTests`：ConnectionsSheet（有连接 / 未连接）、TodayCardView（`@testable import ZephyrFeatures`，二者是 internal）。
  - `ComponentSnapshotTests`：ZConnectButton 全部 phase + accent tint、ZLatencyPill 各档 × text/pill、ZFlag regular/small/highlighted、ZBadge 全部 tone × filled。
  - `WidgetSnapshotTests`：StatusSmall（4 种状态）、UsageSmall（含空）、StatusMedium、ScenesMedium（含边界 / 空）、锁屏 circular / rectangular / inline、零件陈列。
  - `LiveActivitySnapshotTests`：锁屏卡片（含边界 / 连接中）、灵动岛紧凑 / 最小 / 展开。
  - `L2PagesSnapshotTests`：SubscriptionsView(engine:now:)、SettingsView(engine:)、LibrarySheet(engine:onOpen:)、OnboardingView(engine:onFinish:)，整文件包在 `#if ZEPHYR_L2_PAGES`。
- 保留了 A 的 `SnapshotSmokeTests.swift`，未改。

### 单测（`Shared/Tests/`，target `ZephyrTests`）
- `SharedStoreTests`：往返、磁盘 JSON 形态（sortedKeys / 毫秒时间）、读-改-写不覆盖他人字段、缺失 / 损坏 / 截断 / 二进制 / schema 不兼容 → `.empty`、损坏后 update 从空开始、reset、Rate.push 容量、跨天用量清零。
- `PendingCommandTests`：投递即取、取出即删、TTL 边界（含）与过期删除、后投递覆盖、损坏文件、编解码。
- `TunnelMessageTests`：请求 / 响应往返、**线上格式固定**（`{"status":{}}`、`{"setMode":{"_0":"global"}}`）、未知请求 → nil、多余字段忽略、< 1 KB。
- `TunnelNetworkSettingsFactoryTests`：IPv4 地址 / 默认路由 / LAN 排除、IPv6 开关与排除、DNS `matchDomains [""]`、MTU、HTTP 代理；`TunnelConfiguration.load` 默认值 / MTU 夹取 / options 覆盖 / 非法值忽略。
- `MihomoBridgeTests`：桩模式参数校验、start/stop/reload 状态机、流量恒 0、模式记录、并发安全（链接真核心时整组 `XCTSkip`）。
- `MappedFileTests`：内容 / 长度 / prefix 截断 / 空文件 / NUL 与非法 UTF-8 / 只看前 512 字节 / 1 MiB 内容一致 / ENOENT / 删除路径后映射仍可读。
- A 的 `TunnelConfigurationTests.swift` 未改。

### 工程 / 文档
- `project.yml`：`NSCameraUsageDescription` 改为“扫描订阅二维码”（保留 `NSLocalNetworkUsageDescription`，本地端口共享需要）；快照 target 额外排除 `**/__Snapshots__/**`；补注释。
- `App/Localizable.xcstrings`：新建空 String Catalog（sourceLanguage zh-Hans）。仓库里原本没有任何 `.xcstrings`；App 目录整体进 App target，XcodeGen 2.38+ 自动放进 Resources。
- `README.md`、`.gitignore`、本文件。

## 需要 A 提供 / 确认

### 1. mihomo 核心：xcframework 与 C 符号（**当前对不上**）
`PacketTunnel/MihomoBridge/include/mihomo.h` 与 `MihomoBridge.swift` 按 `mihomo_*` ABI 写，期望 `Mihomo.xcframework`；
但 A 的 `tools/build-mihomo.sh ios` 实际产出 **`build/ios/Zmihomo.xcframework`**（`libzmihomo.a` + `zmihomo.h` + `module Zmihomo`），导出的是 **`zm_*`**：

| 现 Swift 期望（mihomo.h） | mihomo-mobile/zmihomo.go 实际导出 |
|---|---|
| `int32_t mihomo_start(const char *config_path, int32_t tun_fd)` | `char *zm_start(char *homeDir, char *cfg, char *ctlSock)` → 错误串（需 `zm_free`），**没有 tun fd 参数** |
| `void mihomo_stop(void)` | `void zm_stop(void)` |
| `mihomo_traffic_t mihomo_traffic(void)` | `void zm_traffic(int64_t *up, int64_t *down, int64_t *upTotal, int64_t *downTotal)` |
| `int32_t mihomo_reload(const char *)` | `char *zm_reload(char *cfg)` → 错误串 |
| `int32_t mihomo_set_mode(const char *)` | **无**（需经 ctlSock 的 external-controller，或补导出） |
| `void mihomo_set_memory_limit(int64_t)` | `void zm_set_memory_limit(int64_t)`（同时把 GCPercent 设为 50） |
| `void mihomo_free_os_memory(void)` | `void zm_free_os_memory(void)` |
| `const char *mihomo_last_error(void)` | 无（错误随返回值给出）；另有 `zm_running` / `zm_memory` / `zm_version` / `zm_free` |

需要 A 决定二选一：
- (a) mihomo-mobile 增加与 `mihomo.h` 一致的导出（含 tun fd、set_mode、last_error）；或
- (b) 以 `zmihomo.h` 为准，X 改写 `MihomoBridge.swift`（`import Zmihomo`，不再用桥接头），并回答：**iOS 上 tun fd 怎么交给核心**——放进运行时配置（`tun.file-descriptor`）由 core-mobile 生成，还是另加参数？`ctlSock` 在 NE 沙盒里用 App Group 内的 unix socket 路径是否可行（路径长度上限 104 字节）？

确认后 X 在 `project.yml` 的 PacketTunnel 加 `- framework: ../../build/ios/Zmihomo.xcframework`（embed: false）、`MIHOMO_LINKED`、`-lresolv`。
注意：一旦对 ZephyrTests 也定义 `MIHOMO_LINKED`，它没有桥接头会编译失败——保持只在 PacketTunnel 定义。

同理 `ZephyrMobileCore.xcframework`（`tools/build-ios-xcframework.sh` → `build/ios/` + `build/ios/Sources/*.swift`）目前也没有被任何 target 引用；`EngineFactory` 的 `canImport(ZephyrCore)` 分支要等 K/A 把 ZephyrCore 加进 Package.swift。CI 每次都在构建这两个 xcframework 但工程没链接，属于白跑，可考虑暂时跳过或尽快接上。

### 2. 签名
- Apple Developer **Team ID**（写进 `project.yml` 的 `DEVELOPMENT_TEAM`，或只在本地 xcconfig 里覆盖）。
- 三个 Bundle ID 的注册与能力：`app.zephyr.mobile`（App Groups、Network Extensions: Packet Tunnel、Push 不需要）、`app.zephyr.mobile.PacketTunnel`（App Groups、Network Extensions）、`app.zephyr.mobile.Widgets`（App Groups）。
- App Group `group.app.zephyr.mobile` 注册到上述三个 ID。
- Provisioning：开发用 Automatic 即可；如要 CI 出 TestFlight 包，需要 Distribution 证书 + 三个 App Store profile（建议 fastlane match 或 App Store Connect API Key），并在 CI 用 secrets 注入；目前 CI 只跑无签名的模拟器测试，不需要。

### 3. CI：快照参考图 artifact（建议改 `.github/workflows/mobile.yml` 的 ios job，X 无权限改）
现在首跑会在 runner 上把参考图录进 `apps/ios/SnapshotTests/__Snapshots__/`，但只在失败时上传 xcresult，录出来的图拿不到。建议：

```yaml
      - name: 上传快照参考图（录制 / 更新）
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ios-snapshots
          path: apps/ios/SnapshotTests/__Snapshots__
          if-no-files-found: ignore
      - name: 上传快照失败对比图
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: ios-snapshot-failures
          path: ${{ runner.temp }}/snapshot-artifacts
```
并在 build & test 步骤加 `env: TEST_RUNNER_SNAPSHOT_ARTIFACTS: ${{ runner.temp }}/snapshot-artifacts`。
流程：第一次 CI 跑完下载 `ios-snapshots`，人工过一遍后提交进仓库；之后再把 scheme 的 `SNAPSHOT_RECORD` 改成 `never`，防止新用例漏录。
参考图应在 CI 同款环境（macos-15 + iPhone 16 模拟器）录制，本地不同 Xcode 版本录的图可能因字体渲染差异而失败。

## 已知缺口 / 风险
- `@testable import ZephyrFeatures`（ActivitySnapshotTests）依赖 Debug 下本地包以 `-enable-testing` 编译（Xcode 对 Debug 包默认如此）。若 CI 报 “module not compiled for testing”，删掉该文件或让 H 把 ConnectionsSheet / TodayCardView 改成 public。
- 工作区里 H 把原 `Activity/ConnectionsSheet.swift` 换成了“刚才”列表实现，并保留了兼容名 `ConnectionsSheet(initialTraceID:)`（注释写明给本快照用例用）。若之后删掉兼容名，需同步改 `ActivitySnapshotTests`。
- 渲染用 `layer.render`：材质模糊（`UIVisualEffectView` / `.ultraThinMaterial`）与 Metal 背书的 `drawingGroup` 不会被如实画出。
- 首页曲线若依赖 `TimelineView` 的真实时间，参考图之间可能有细微差异（靠 0.98 感知精度兜住）；如出现抖动，请 H 在冻结时钟下停止 TimelineView。
- L2 用例里 `OnboardingView(engine:onFinish: () -> Void)`、`SubscriptionsView(engine:now: @Sendable () -> Int64)`、`LibrarySheet(engine:onOpen: (LibraryItem) -> Void)`、`SettingsView(engine:)` 已与工作区里 L2 的当前签名核对一致（未编译验证）。

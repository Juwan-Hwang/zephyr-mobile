# NOTES-K — ZephyrKit / ZephyrMock（K）

## 做了什么
- `Sources/ZephyrKit/Models.swift`、`ZephyrEngine.swift`：按 `contract/zephyr-engine.md` v0 **整体重写**（旧草案已替换）。所有类型 `public`、`Sendable`、`Hashable`、`Codable`，带 public memberwise init；序列化名 snake_case（CodingKeys），枚举 rawValue = 契约序列化名。
- `Sources/ZephyrKit/Format.swift`：`ZFormat`。
- `Sources/ZephyrMock/*`：`MockEngine` 完整实现 + 确定性算法移植（`MockNodes` hsh/nodeName/cachedLatency，`MockQuery` buildModel/rowAt，`MockRules` matchRule，`MockFixtures` 场景/订阅/今日/设置固定值，`MockCommands` 命令搜索，`Broadcaster` 流分发，`MockClock`）。
- `Package.swift`：Linux 上只声明 ZephyrKit/ZephyrMock 及其测试目标（`#if !os(Linux)` 才加入 SwiftUI 目标），否则 `swift test` 会去编 SwiftUI 失败。Apple 平台上目标列表与原来相同。
- 测试：`Tests/ZephyrKitTests`（Format、Codable 键名、行号定位）、`Tests/ZephyrMockTests`（fixtures 逐项、引擎行为、并发、性能）。

## Linux 上怎么跑
```
export PATH=/workspace/tools/swift-6.1.2-RELEASE-debian12-aarch64/usr/bin:$PATH
cd apps/ios/Packages/ZephyrKit
swift test --filter ZephyrMockTests   # 19 个
swift test --filter ZephyrKitTests    # 9 个
```
在 `-strict-concurrency=complete` 下零警告。

## API 速览（契约之外 K 补充的名字）
- `typealias NodeId = UInt64`
- 契约里的匿名返回值命名为：`SubscriptionsSummary { count: Int32, totalNodes: Int64 }`、`StorageInfo { nodesBytes, rulesBytes, freeBytes }`
- 契约里的内联枚举命名为：`NetworkKind`、`SceneSource`（`.subscriptionGroup` = "subscription_group"）、`Accent`、`Appearance`
- 契约未展开的 `DnsSettings`（fakeIp/nameservers/fallback/ipv6）、`TunSettings`（stack: TunStack/mtu/ipv6/strictRoute）是 K 的最小定义，A 定版后按契约改。
- 虚拟列表辅助：`NodeQueryResult.rowCount`，`[RegionSection].locate(row:) -> NodeListRow?`（`.header(section:)` / `.node(section:indexInSection:ordinal:)`，ordinal 直接作 `nodeRows` 的 offset）。
- 方法参数标签照抄契约：`setMode(mode:)`、`setGlobalNode(id:)`、`sceneCandidates(sceneId:region:)`、`nodeRows(token:offset:limit:)`、`testLatency(ids:)`、`logs(minLevel:)`、`updateSettings(patch:)`…
- `recentTraffic(seconds:)` 与各流返回函数按契约是同步的（无 async）。

## MockEngine 约定
- `MockEngine(seed: 0, clock: .live, startConnected: nil)`：`startConnected == nil` 时，冻结时钟下初始**已连接**（since = 9:41 − 2:14:07），实时时钟下未连接。
- `MockClock.frozen941` = 2026-11-06 09:41 +08:00（`1_793_929_260_000`），`realDelays = false`：connect / 测速 / 导入等**立即完成**，无 1 Hz 定时器；traffic 流只发一次当前样本（2.8 MB/s ↓ · 194 KB/s ↑，与原型首页一致）。
- `.live`：connect 600 ms；测速每个节点 80–400 ms（按 50 ms 分桶批量推送）；流量与活动连接 1 Hz。
- 查询 token：`""` 永远是 token 0；其他查询的 token 递增，最多保留最近 128 个，过期 token → `ZephyrError(.internal)`。
- 场景 / 全局出口里有名字的节点（新加坡 02、东京 03、香港 HKT、US-Fixed-01、TW-Fixed-01…）是**具名节点**，ID = `region*1e8 + 90_000_000 + k`（在生成节点范围之外），`node(id:)`、`setGlobalNode`、`applySceneChange` 都能解析。
- seed 只影响流量抖动和非 Nebula 订阅的 diff；节点库/规则/场景与 seed 无关（必须对齐 fixtures）。

## 测试结果（Linux aarch64，Swift 6.1.2，debug）
- ZephyrMockTests 19/19，ZephyrKitTests 9/9 通过。
- fixtures：15 地区、总数 13,109,802、277 个节点样本（名/tag/协议/运营商/城市/hash/缓存延迟）、16 条查询（计数、分区、前 12 行含头行）、13 条规则样本、规则总数 103,606,731，全部一致。
- 性能（15 次中位数，debug 构建）：queryNodes 最坏 ≈ 0.34 ms（< 5 ms）；nodeRows 500 行最坏 ≈ 1.2 ms（< 2 ms）。

## 已知偏差 / 判断
1. **IPv6**：原型只认 IPv4 为 IP；Mock 把 IPv6 也当 IP（isIp = true，只进第 7 层，落到 MATCH）。fixtures 无 IPv6 样本。
2. **测速值**按 mock-spec §6（缓存值优先，否则 `hsh%23==0` → -1，否则 base + hsh%37），不是原型 `settle()` 里的 `h%13`/`h%41` 公式。
3. 视频场景出口按 mock-spec 用 `203.0.113.24`（原型 CPOOL 写 198.51.100.51）；US-Fixed-01 出口改成 `203.0.113.28` 以免与视频出口重复。TW-Fixed-01 延迟原型没给，取 52 ms。
4. "其他"场景 `available` 原型显示"—"，契约是非可选 Int32 → 填 0，UI 对 `source == .subscriptionGroup` 显示"—"。
5. 今日 `hourly` 按 spec 24 项总和 = 1.8 GB（包括 9:41 之后的小时）。
6. 到期文案规则（K 定）：≥ 7 天 "26 天后到期"，1–6 天 "11月9日到期"，当天 "今天到期"，已过 "已到期"。原型订阅页 Orbit 另有一处写"周一到期"，未采用。
7. `ZFormat.duration` 始终 `h:mm:ss`（"0:04:07"），计时器宽度稳定。
8. 导入订阅不改变节点库总数（Mock 节点库固定 13,109,802）。
9. 策略组是 Mock 自定的 6 个（节点选择/自动选择/故障转移/负载均衡/香港/美国），成员来自节点库查询。

## 需要别人配合
- A：契约里 `DnsSettings` / `TunSettings` 字段、"订阅不存在"错误码（目前用 `subscription_invalid`）、"查询 token 过期"错误码（目前用 `internal`）待定。
- 所有人：用 `MockEngine(clock: .frozen941)` 做 Preview/快照，数据与原型 9:41 截图一致。

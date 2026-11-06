# ZephyrEngine 接口契约 v0

> 归属：A（Agent-Hark）。状态：**v0 草案，可按此开工**。改动走 PR，并在看板 #1 @ iOS / Android。
> 来源：`design/prototype/`（数据与交互）、`design/notes/mobile-design-spec.md`（IA）、`design/notes/scale-architecture.md`（规模）。
> 两端实现：Swift `ZephyrKit.ZephyrEngine`（protocol）、Kotlin `:core-engine` `ZephyrEngine`（interface）。各有 `MockEngine`（按 `mock-spec.md` 生成，同种子同结果）与 `CoreEngine`（包 UniFFI，来自 `core-mobile/`）。

## 0. 总原则
1. **规模优先**：任何"列表"都不返回全量。节点/规则只给 **计数 + 分区索引 + 按需分页**。UI 不得假设能拿到全部条目。
2. **全部异步**：Swift `async throws` + `AsyncStream`；Kotlin `suspend` + `Flow`。实现保证线程安全，可在任意线程调用。
3. **ID 稳定**：`NodeId` 是 `UInt64`（Kotlin `Long`），同一订阅内跨更新保持不变（核心用 server+port+protocol 指纹；Mock 用 `region * 100_000_000 + index`）。
4. **时间**：毫秒 Unix 时间戳 `Int64`。**速率**：字节/秒 `Int64`。**流量**：字节 `Int64`。**延迟**：毫秒 `Int32`，`null` = 未测/缓存过期，`-1` = 超时。
5. **错误**：统一 `ZephyrError { code: ErrorCode, message: String }`，`ErrorCode` 见 §9。文案不由引擎给，UI 按 code 本地化；`message` 只用于日志。
6. 命名：下文用中性伪 IDL。Swift 用 lowerCamelCase 原样，Kotlin 同名。枚举值 Swift `.ruleMode`、Kotlin `RULE_MODE` 皆可，但**序列化名**以下文 snake_case 为准（fixtures / UniFFI 用）。

## 1. 连接与模式
```
enum ConnectionStatus { disconnected, connecting, connected, disconnecting, failed }
enum ProxyMode { rule, global, direct }

record ConnectionState {
  status: ConnectionStatus
  mode: ProxyMode
  since: Int64?            // 进入 connected 的时间
  globalNodeId: NodeId?    // mode == global 时的出口
  network: NetworkInfo?    // 当前网络
  error: ZephyrError?      // status == failed
}
record NetworkInfo { kind: wifi|cellular|ethernet|other, name: String?, trusted: Bool }

connectionState() -> Stream<ConnectionState>     // 立即发当前值，之后变化即发
connect() async throws                            // 平台层先启动 VPN/NE，再调此方法
disconnect() async throws
setMode(mode: ProxyMode) async throws
setGlobalNode(id: NodeId) async throws -> ExitChange
```

## 2. 流量与用量
```
record TrafficSample { at: Int64, upBps: Int64, downBps: Int64 }
record UsageSummary {
  todayBytes: Int64
  regionsToday: Int32        // "4 个地区"
  onlineMillisToday: Int64   // "6 小时在线"
  fastestLatencyMs: Int32?   // "38 ms 最快"
  hourly: [Int64]            // 24 个，今日每小时字节（"今日"图案用）
}
traffic() -> Stream<TrafficSample>     // 1 Hz；未连接时不发
recentTraffic(seconds: Int32) -> [TrafficSample]   // 迷你曲线回填，最多 300
usageToday() async -> UsageSummary
```

## 3. 场景（Scene，首页核心）
场景 = 按用途分的出口池（原型：AI / 视频 / 其他）。每个场景有候选池、当前节点、出口 IP、检测时间，以及"例外"（如 Claude 固定 US）。
```
enum SceneKind { ai, video, other, custom }
record Scene {
  id: String                 // "ai" | "video" | "other" | 自定义 uuid
  kind: SceneKind
  name: String               // "AI"
  available: Int32           // "9 个可用"
  selected: NodeSummary      // 当前出口节点
  exitIp: String?            // "198.51.100.7"
  source: auto|manual|subscription_group   // "订阅分组"
  testedAt: Int64?
  note: String?              // "Netflix 完整片库"
  exceptions: [SceneException]
}
record SceneException { app: String, node: NodeSummary }   // "Claude：US-Fixed-01"
record ExitChange {             // 用于"更改出口 IP？"确认弹层
  sceneId: String?              // null = 全局
  fromRegion: String, fromIp: String?
  toRegion: String,   toIp: String?
  affectedApps: [String]        // "GPT 和 Gemini"
  unchangedApps: [String]       // "Claude 保持不变"
}
scenes() -> Stream<[Scene]>
sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary]   // 左右滑动切地区；按延迟排序，最多 50
previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ExitChange
applySceneChange(sceneId: String, nodeId: NodeId) async throws      // UI 需支持"撤销"：再 apply 旧节点
retestScene(sceneId: String) async throws -> Scene
```

## 4. 策略组（mihomo proxy-groups，"代理"页）
```
enum GroupType { select, url_test, fallback, load_balance, relay }
record PolicyGroup { name: String, type: GroupType, selected: String?, memberCount: Int32, testedAt: Int64? }
policyGroups() -> Stream<[PolicyGroup]>
groupMembers(group: String, offset: Int32, limit: Int32) async throws -> NodePage   // limit ≤ 500
selectInGroup(group: String, nodeId: NodeId) async throws
testGroup(group: String) async throws     // 只测该组，结果经 latencyUpdates 推送
```

## 5. 节点库（千万级）
```
record NodeSummary {
  id: NodeId
  name: String               // "东京 NTT IPLC 03 ×1.5"
  region: String             // ISO 3166 alpha-2，"JP"
  city: String?
  carrier: String?
  tag: String?               // IPLC|IEPL|BGP|家宽|原生
  protocol: String           // VLESS|Hy2|TUIC|SS|Trojan
  multiplier: Float?         // 1.5 / 0.5 / 2
  latencyMs: Int32?          // 只给缓存值
}
record RegionSection { region: String, name: String, count: Int64, rowOffset: Int64 }   // rowOffset 含分区头行
record NodeIndex { total: Int64, sections: [RegionSection], testedCount: Int64 }
record NodeQueryResult {
  query: String
  total: Int64
  sections: [RegionSection]        // 只含命中的分区，rowOffset 按结果重排
  highlights: [String]             // UI 高亮的词
  tookMicros: Int64
  token: Int64                     // 结果句柄，配合 nodeRows 分页
}
record NodePage { rows: [NodeSummary], offset: Int64, total: Int64 }

nodeIndex() async -> NodeIndex
queryNodes(query: String) async throws -> NodeQueryResult       // "" = 全部；绝不扫全表，见 mock-spec §3
nodeRows(token: Int64, offset: Int64, limit: Int32) async throws -> NodePage   // offset 为节点序号（不含分区头），limit ≤ 500
node(id: NodeId) async throws -> NodeDetail
testLatency(ids: [NodeId]) async          // 只测可见行（UI 停止滚动 400ms 后调用），≤ 100 个
latencyUpdates() -> Stream<[LatencyUpdate]>
record LatencyUpdate { id: NodeId, latencyMs: Int32, at: Int64 }
record NodeDetail { summary: NodeSummary, server: String (已脱敏), port: Int32, subscription: String, extra: Map<String,String> }
```
UI 约定：虚拟列表总行数 = `total + sections.count`（每个分区一行头）。行号→(分区, 序号) 用 `rowOffset` 二分。

## 6. 规则
```
enum LayerKind { override, subscription, domain, ip }
record RuleLayer { index: Int32, kind: LayerKind, name: String, count: Int64, note: String, updatedAt: Int64? }
record RuleStats { total: Int64, layers: [RuleLayer], compiled: Bool, diskBytes: Int64 }
record RuleTrace {
  input: String
  isIp: Bool
  layerIndex: Int32?          // null = 落到 MATCH（第 layers.count+1 层"其余流量"）
  rule: String                // "DOMAIN-SUFFIX,github.com" | "MATCH"
  ruleNo: Int64?              // 该层内序号，"#41"
  policy: String              // "DIRECT" | "REJECT" | 场景 id
  scene: Scene?               // policy 是场景时
  exitIp: String?
  tookMicros: Int64
}
ruleStats() async -> RuleStats
testRule(input: String) async throws -> RuleTrace     // 域名或 IPv4/IPv6；O(len)
```

## 7. 订阅与配置
```
record Subscription {
  id: String, name: String, url: String? (脱敏)
  nodeCount: Int64
  usedBytes: Int64?, totalBytes: Int64?, remainingBytes: Int64?
  expiresAt: Int64?
  updatedAt: Int64?
  autoUpdateHours: Int32
  lastDiff: SubscriptionDiff?
}
record SubscriptionDiff { addedNodes: Int64, removedNodes: Int64, ruleChanges: Int64, overridesKept: Bool, scenesRetested: Bool }
enum ImportSource { url, clipboard, qr, file }
subscriptions() -> Stream<[Subscription]>
subscriptionsSummary() async -> { count: Int32, totalNodes: Int64 }      // "其他 212 个 · 13,098,480 个节点"
importSubscription(source: ImportSource, payload: String) async throws -> Subscription   // file 时 payload = 文件内容
previewUpdate(id: String) async throws -> SubscriptionDiff      // "更新前显示更改"
updateSubscription(id: String) async throws -> SubscriptionDiff
updateAll() async throws -> [SubscriptionDiff]
deleteSubscription(id: String) async throws
```

## 8. 连接、日志、设置
```
record ConnectionInfo { id: String, host: String, app: String?, scene: String?, node: String, upBytes: Int64, downBytes: Int64, startedAt: Int64 }
activeConnections() -> Stream<[ConnectionInfo]>     // 最多 200 条最新
closeConnection(id: String) async throws
closeAll() async throws

enum LogLevel { debug, info, warning, error }
record LogLine { at: Int64, level: LogLevel, message: String }
logs(minLevel: LogLevel) -> Stream<LogLine>

record Settings {
  onDemand: Bool, trustedWifi: [String], disconnectOnTrusted: Bool
  localProxyPort: Int32, localProxyAuth: Bool
  testOnWifiOnly: Bool, latencyTtlHours: Int32
  autoUpdateHours: Int32, updateOnWifiOnly: Bool, showChangesBeforeUpdate: Bool
  dns: DnsSettings, tun: TunSettings
  accent: blue|green|orange|pink, appearance: system|dark|light
  shareAnonymousPattern: Bool     // "图案由今天的流量生成，不含节点名称与 IP"
}
settings() -> Stream<Settings>
updateSettings(patch: Settings) async throws    // 全量写回
storage() async -> { nodesBytes: Int64, rulesBytes: Int64, freeBytes: Int64 }
```

## 9. 命令搜索（首页"搜索或输入指令"）
```
enum CommandKind { switch_node, switch_mode, open_node_query, test_rule, open_page, toggle_connection }
record CommandSuggestion { kind: CommandKind, title: String, subtitle: String?, payload: String }
commandSuggestions(input: String) async -> [CommandSuggestion]   // ≤ 8 条；空输入给"建议"
```
mock 规则：输入像域名/IP → test_rule；匹配地区/城市/运营商/标签 → open_node_query + 最快节点 switch_node；"全局/规则/直连" → switch_mode。

## 10. ErrorCode
`not_running, vpn_permission_denied, network_unavailable, subscription_invalid, subscription_fetch_failed, node_not_found, scene_not_found, group_not_found, rule_input_invalid, core_crashed, storage_full, cancelled, internal`

## 11. 平台层（不在引擎内）
- iOS：NEPacketTunnelProvider 里把 tun fd 交给核心（mihomo 以库嵌入，**禁止 Process()**）；App 与扩展经 App Group + Darwin notify 通信；引擎在 App 侧是扩展的代理。
- Android：VpnService 建 tun，fd 经 `inject_tun_fd` 交核心；前台服务常驻通知；QS Tile 与 Glance 读 `connectionState()`。
- 小组件/实时活动/控制中心只读：`ConnectionState`、`TrafficSample`、当前场景摘要。

## 12. 版本
- v0（2026-11-06）首版。后续加字段只追加、不改名；破坏性改动升 v1 并在看板公告。

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

v0.1 追加：`stale_token`（查询句柄已淘汰，UI 重新 queryNodes 即可，不提示用户）、`subscription_not_found`（删除/更新不存在的订阅）。

## 11. 平台层（不在引擎内）
- iOS：NEPacketTunnelProvider 里把 tun fd 交给核心（mihomo 以库嵌入，**禁止 Process()**）；App 与扩展经 App Group + Darwin notify 通信；引擎在 App 侧是扩展的代理。
- Android：VpnService 建 tun，fd 经 `inject_tun_fd` 交核心；前台服务常驻通知；QS Tile 与 Glance 读 `connectionState()`。
- 小组件/实时活动/控制中心只读：`ConnectionState`、`TrafficSample`、当前场景摘要。

## 12. 版本
- v0（2026-11-06）首版。后续加字段只追加、不改名；破坏性改动升 v1 并在看板公告。
- v0.1（2026-11-06 14:20）追加 §13：类型命名、Dns/Tun 设置、stale_token / subscription_not_found、IPv6 规则测试、连接轨迹。

## 13. v0.1 追加（2026-11-06 14:20，只追加不改名）
采纳 iOS NOTES-K 的命名，两端照此：

```
// 原匿名类型命名
enum NetworkKind { wifi, cellular, ethernet, other }
enum SceneSource { auto, manual, subscription_group }
enum Accent { blue, green, orange, pink }
enum Appearance { system, dark, light }
record SubscriptionsSummary { count: Int32, totalNodes: Int64 }
record StorageInfo { nodesBytes: Int64, rulesBytes: Int64, freeBytes: Int64 }

// Settings 内未展开的两项
record DnsSettings { fakeIp: Bool, nameservers: [String], fallback: [String], ipv6: Bool }
enum TunStack { system, gvisor, mixed }
record TunSettings { stack: TunStack, mtu: Int32, ipv6: Bool, strictRoute: Bool }
```
默认值（Mock 与首次启动一致）：`DnsSettings(fakeIp: true, nameservers: ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"], fallback: ["https://1.1.1.1/dns-query"], ipv6: false)`，`TunSettings(stack: gvisor, mtu: 9000, ipv6: false, strictRoute: true)`。iOS NE 默认 gvisor；Android 同。

### 规则测试与 IPv6
- 输入 IPv6 字面量（含 `[...]`）按 IP 处理：域名层（1–5）跳过，只走 IP 层（IP-CIDR6/GEOIP）与 MATCH。fixtures 无样本；Mock 落到 MATCH 即正确。
- core-mobile 的 IP 层同时支持 IP-CIDR 与 IP-CIDR6（压平区段 + 二分），`[...]` 包裹的输入同样识别。

### 连接轨迹（原型 trace sheet：规则 → 场景 → 节点 → 出口 + 本次覆写）
```
record ConnectionTrace {
  host: String                 // "claude.ai"
  lastSeenAt: Int64            // "3 秒前"
  connections: Int32           // "17 个连接"
  totalBytes: Int64            // "2.1 MB"
  rule: String                 // "DOMAIN-SUFFIX,claude.ai"
  ruleSource: String?          // "Nebula Cloud"（规则集/订阅名；Zephyr 覆写 = "Zephyr 覆写"）
  scene: String?               // 场景 id，直连 = null
  sceneSource: String?         // "Zephyr 优选"
  node: NodeSummary?           // 直连 = null
  via: String?                 // "US Fixed IP · 固定"
  exitIp: String?, exitRegion: String?, exitStableDays: Int32?   // "203.0.113.24 美国 · 7 天未变化"
  override: TraceOverride?     // 当前生效的覆写
}
enum TraceTarget { unchanged, direct, scene }     // 分段：不变 / 直连 / 视频 / 其他…（scene 时带 sceneId）
record TraceOverride { target: TraceTarget, sceneId: String?, persistent: Bool }
recentHosts(limit: Int32) -> Stream<[ConnectionInfo]>        // "最近连接"，按 host 聚合，最多 limit（≤ 50）
connectionTrace(host: String) async throws -> ConnectionTrace // host 无记录 → node_not_found
overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Bool) async throws
// persistent = false 只影响本次（直到该 host 的连接全部关闭）；true 写入 Zephyr 覆写层（规则第 1 层），订阅更新时保留
```
iOS 不提供发起连接的 App，`ConnectionInfo.app` 在 iOS 恒为 null，UI 显示"仅显示域名"说明。

Mock 固定值（与原型 9:41 一致）：最近连接 5 条 —— claude.ai（AI · US-Fixed-01 · 2.1 MB）、nflxvideo.net（视频 · 香港 HKT · 184 MB）、gemini.google.com（AI · 新加坡 02 · 640 KB）、github.com（其他 · TW-Fixed-01 · 12 MB）、qq.com（直连 · 3.4 MB）；claude.ai 的轨迹见上方注释中的原型文案（17 个连接、3 秒前、出口 203.0.113.24 美国 7 天未变化）。

## 14. v0.2 追加（2026-11-06 15:35，core-mobile 已实现，只追加）
真实实现在 `core-mobile`（UniFFI，`MobileCore` / `MihomoClient`），绑定见 `core-mobile/bindings`。与 §3/§5/§7/§8 的 Stream/async 形态不同：核心是同步调用，平台层自己包成 Stream/async 并放后台线程。B/C 的 MockEngine 继续按 §1–§13 的形态，真实引擎适配层把两者对上。

### 订阅（§7 的真实形态：平台拉取，核心解析）
```
record FetchedSubscription { body: String, userinfo: String?, nowMillis: Int64 }   // userinfo = 原样的 subscription-userinfo 头
subscriptionFetchUrl(id) -> String?          // 平台用它发请求（SSRF/DNS 校验在平台层）
dueSubscriptions(nowMillis) -> [String]      // 到期需自动更新的 id
importSubscription(name, url?, fetched, autoUpdateHours, progress?) -> Subscription
previewSubscriptionUpdate(id, fetched) -> SubscriptionDiff   // 改名不算增删；空列表拒绝覆盖
updateSubscription(id, fetched, progress?) -> SubscriptionDiff
deleteSubscription(id); subscriptions(); subscriptionsSummary()
```
正文规整、URL/名称校验、URL 脱敏复用桌面 zephyr-core（base64 解码、short-id 加引号、控制面字段清洗）。

### 延迟与优选（§5 补充）
```
record LatencySample { id: NodeId, ms: Int32 /* -1 超时 */, at: Int64 }
record RankedNode { row: NodeRow, latencyMs: Int32, testedAt: Int64, score: Double }   // ⚠ score 为新增字段（破坏性）
recordLatencies([LatencySample]); cachedLatencies([NodeId], nowMillis, maxAgeMillis) -> [Int32?]
fastestNodes(query, limit, nowMillis, maxAgeMillis) -> [RankedNode]   // 桌面 smart_selector 打分：P90 + 成功率 + 稳定性
```

### 运行时配置
```
record RuntimeOptions { dns, tun, mode, controllerSocket, findProcess, logLevel }
runtimeConfig(subscriptionId, RuntimeOptions) -> String   // mihomo YAML，交给 zm_start / zm_reload
```
控制入口只有 `external-controller-unix`（无 TCP 端口）；TUN 用系统 fd，auto-route 关。场景组、例外组、覆写规则在这里注入。

### 场景（§3 的真实形态）
```
scenes(nowMillis) -> [Scene]        // Scene 增加 group（mihomo 组名）、selectedLatencyMs、exitRegion；selected 可空（未选=不接管流量）
sceneCandidates(sceneId, region?, nowMillis) -> [RankedNode]   // region 空 = 当前节点地区；≤50，24h 内测过
previewSceneChange(sceneId, nodeId) -> ExitChange              // toIp 恒 null（连上才知道）
applySceneChange(sceneId, nodeId, nowMillis) -> SceneApply
record SceneApply { needsReload: Bool, group: String, member: String, previous: NodeId? }
  // needsReload=false：MihomoClient.selectInGroup(group, member) 即可（热备成员，零中断）
  // needsReload=true ：runtimeConfig + zm_reload
  // 撤销 = applySceneChange(sceneId, previous)
reportSceneExit(sceneId, ip, region?, testedAt)    // 平台测得出口后回填
setSceneException(sceneId, appId, nodeId?)         // "Claude：US-Fixed-01"；nodeId=null 删除；需重载
sceneForHost(host) -> String?
```
内置应用目录（appId）：chatgpt、claude、gemini、perplexity、grok（AI）；netflix、youtube、disney、max、primevideo（视频）。
规则顺序：Zephyr 覆写 → 场景例外 → 场景应用域名 → 订阅规则；"其他"场景选了节点时接管 MATCH。

### 覆写（§13 overrideHost 的真实形态）
```
overrideHost(host, target, sceneId?, persistent)   // target=unchanged 即清除；persistent=false 不落盘（进程内有效）；需重载
hostOverride(host) -> HostOverride?
```

### MihomoClient（§4、§8、§13 轨迹的数据源，unix socket REST）
```
MihomoClient(socketPath)
version(); policyGroups(); groupMembers(group, offset, limit ≤500); selectInGroup(group, member)
testGroup(group, url, timeoutMs); activeConnections(limit ≤200); recentHosts(limit); hostTrace(host)
closeConnection(id); closeAllConnections(); setMode(mode)
```

### 存储
`storageInfo() -> StorageInfo { nodesBytes, rulesBytes, subscriptionsBytes, cacheBytes }`（§13 的 freeBytes 由平台层取）。

### 错误码追加
`not_running`（mihomo 未运行或 socket 不通）。`scene_not_found` 已在 §10。

### 场景自动切换（v0.2 追加）
```
record FailoverPolicy { enabled: Bool, threshold: UInt32 /* 默认 3 */, cooldownSecs: UInt64 /* 默认 30 */ }
failoverPolicy() -> FailoverPolicy; setFailoverPolicy(FailoverPolicy)   // threshold/cooldown 为 0 → invalid
reportSceneProbe(sceneId, success, nowMillis) -> SceneFailover?
record SceneFailover { failed: NodeRow, failureCount: UInt32, apply: SceneApply }   // apply.needsReload 恒 false → selectInGroup
```
平台对每个已选节点的场景定期探测出口（或连接失败时）上报；返回非空即已切换，UI 提示"AI 出口已自动切换到 xx（撤销）"。

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
  localProxyPort: Int32, localProxyAuth: Bool, localProxyEnabled: Bool = false   // §14.z
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
- v0.3（2026-11-14）追加 §15：导入载荷 / 桌面同步二维码格式（parseImportPayload）。
- v0.4（2026-11-18）追加 §16：发版审计（#209）的契约补定义——网络与路由、错误码映射、设置默认值、指令语义、格式与无障碍、本地代理凭据、日志级别、订阅拉取、平台差异登记。只追加，不改名。

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

### 规则层 0 由核心保留（v0.2 追加）
`rules/000.zr` = 第 1 层"Zephyr 覆写"，核心在 overrideHost / setSceneException / 首次 applySceneChange 后自动重编并热加载，内容与 runtimeConfig 前插的规则一致；策略写场景 id（"ai"）或 DIRECT。平台编译自己的层请从索引 1 开始。

### §14.x iOS 隧道配置交接（2026-11-07 追加）

- iOS 的 PacketTunnel 不链接 Rust 核心（NE 约 50 MB 内存上限）。App 在 `startVPNTunnel` 之前调用 `runtimeConfig`，`TunConfig.fileDescriptor = -1`，结果原子写到 App Group `core/config.yaml`。
- 扩展拿到 utun fd 后，把唯一一行 `file-descriptor: -1` 替换为真实 fd，再 `zm_start(home=App Group/core, yaml, ctl=App Group/zm.sock)`。找不到哨兵视为配置缺失（`subscription_invalid`）。
- 模式切换：扩展改 YAML 顶层 `mode:` 行后 `zm_reload`，不重建 TUN。
- 订阅更新或场景切换需要重载时，App 先重写 `config.yaml`，再发 `TunnelRequest.reloadConfig`。
- 实时数据（策略组、连接、延迟）：App 经 `MihomoClient(socketPath: App Group/zm.sock)` 读取。

### §14.y 场景自动切换不碰 AI（2026-11-07 追加）

- `reportSceneProbe` 对 kind=AI 的场景恒返回 null，接受上报但不计入失败计数、不自动更换出口（2026-11-08 对齐代码：在计数前返回）。依据：原型 index.html 672–675，AI 出口 IP 只能在用户确认后更改。
- 应用例外（如 Claude 固定出口）不属于场景的 `selected`，任何自动逻辑都不修改。
- 平台对 AI 场景只提示「出口无响应，出口 IP 不会自动更换」。视频、其他、自定义场景照旧在热备内切换。

### 14.z 契约缺口补齐（2026-11-08，回应 B 的 ①–④，只追加）

**① 场景按服务健康**：`Scene.services: [ServiceHealth{appId, name, ok, checkedAt}]`，按内置应用目录顺序；未探测过的服务不出现，空数组 = 不显示服务行。
- 核心：`sceneProbeTargets(sceneId) -> [ProbeTarget{appId, name, url}]`（AI：ChatGPT / Claude / Gemini；视频：Netflix / YouTube；其他：无）；`reportSceneService(sceneId, appId, ok, nowMillis)`。上报只记录，**不触发切换**（AI 出口仅用户确认后更改，§14.y）。
- 出口：`sceneExitProbe(sceneId) -> String?`（Cloudflare trace：AI 用未设例外的 chatgpt.com / claude.ai，其他用 cloudflare.com；视频与自定义为 null）；平台把响应正文交给 `reportSceneTrace(sceneId, body, nowMillis) -> ip`，核心解析 `ip=` / `loc=` 回填 `exitIp` / `exitRegion`（地区代码）/ `testedAt`。
- 平台 `retestScene`：**仅隧道已连接时**经 VPN 探测（请求按域名走规则，测到的就是该服务真实出口，含应用例外）；HEAD 6 s 超时；有响应且状态 <500 且 ≠403 为 ok。未连接只返回缓存。

**② `setSceneSource(sceneId, source)`**：核心 `setSceneSource(sceneId, source, nowMillis) -> SceneApply?`。`auto`（优选）：立即换到延迟缓存里最优节点（当前地区优先，无选择时全库），返回动作由平台执行（needsReload → 重写配置 + reloadConfig；否则 selectInGroup），已最优或无测速数据返回 null；`source` 保持 auto。`manual` / `subscriptionGroup`：只记录。

**③ 写覆写**：平台接口补 `overrideHost(host, target: unchanged|direct|scene, sceneId?, persistent)`（§13 已有核心实现）。隧道运行中平台随后重写配置并 reloadConfig。

**④ 本地代理**：`Settings.localProxyEnabled: Bool`（默认 false，旧数据无此键按 false）。`RuntimeOptions.localProxy: LocalProxy{port: UInt16, auth: "user:pass"?}?`（默认 null）→ `mixed-port` + `bind-address: 127.0.0.1` + `allow-lan: false`（+ `authentication`）；端口 <1024 忽略。凭据由平台本机生成并保存（iOS：`CoreEngine.localProxyCredential()`，形如 `zephyr:<24 位随机>`），设置页展示给用户。

### 14.w 节点详情与按需测速（2026-11-08，只追加）

- 核心 `nodeDetail(id) -> NodeDetail{row, server(脱敏), port, subscription, extra, latencyMs?, latencyAt?}`；extra 只含 network / tls / sni / servername / udp / flow / plugin / cipher / alpn / client-fingerprint，**不含**密码、uuid、私钥。
- 测速：节点库上千万条，运行配置只放场景引用的节点，所以 `testLatency` 不走 mihomo REST。流程：核心 `latencyTestBatch(ids ≤ 512) -> JSON`（name = id 十六进制）→ mihomo-mobile `zm_url_test(json, url, timeoutMs, concurrency)` 临时建出站测 → 核心 `recordUrlTest(resultJson, nowMillis) -> [LatencySample]` 入缓存，平台推 `latencyUpdates`。
- iOS：在扩展里跑（provider message `urlTest(file, url, timeoutMs)`，定义写 App Group core 目录文件，结果在 `TunnelResponse.payload`）；隧道未连接时暂不测（App 进程未链接 mihomo，待定）。Android：VPN 进程或 App 进程直接调 `zm_url_test`（不依赖 zm_start）。
- `nodeIndex.testedCount` = 核心 `testedCount(nowMillis, maxAgeMillis)`（24 h 内有结果的节点数，含超时）。
- 日志（§8 logs）：mihomo-mobile `zm_logs(since, minLevel, limit)` 返回嵌入进程内环形缓冲（500 条）里序号 > since 的行（`{"seq","lines":[{seq,level,msg,at}]}`）。iOS 经 provider message `logs(since, minLevel, limit)`，1 Hz 增量；扩展重启（seq 变小）从 0 重拉。Android 直接调用。
- 全局出口（§1 setGlobalNode）：核心 `previewGlobalChange(nodeId) -> ExitChange`（sceneId=null，影响全部应用）、`setGlobalNode(nodeId) -> SceneApply`（group 恒为 "GLOBAL"；节点此前不在配置里时 needsReload）、`globalNode()`。平台：needsReload 先重写配置并 reloadConfig，然后**总是** selectInGroup("GLOBAL", member)。
- 今日用量（§2 usageToday，iOS）：扩展按 mihomo 累计计数写 App Group/core/usage.json（UsageLedger：24 小时桶、在线毫秒，计数器归零按重启处理，跨天清零），App 只读；regionsToday = 当前各场景/全局出口的不同地区数；fastestLatencyMs = 24 h 内最快节点。
- 命令搜索（§9）：平台用真实引擎实现同一套规则（testRule / queryNodes / fastestNodes），不再依赖 mock。
- 订阅规则层：核心在导入/更新/删除订阅后自动把生效订阅（列表第一个，与运行配置同源）的 rules 编译为第 2 层"订阅规则"（rules/001.zr），MATCH 去向作为最终策略；第 1 层"Zephyr 覆写"恒存在（可为空），层序号稳定。此前订阅规则未进入 testRule / ruleStats，属缺陷。
- 规则集（规则页第 3 层起）：核心 `ruleProviders(nowMillis) -> [RuleProvider{name, url, behavior, format, intervalSecs, policy, layerIndex, ruleCount?, updatedAt?, due}]`（生效订阅里被 RULE-SET 引用的 http 规则集，按首次引用顺序，layerIndex = 2 + 位置）；平台拉正文后 `compileRuleProvider(name, body, nowMillis) -> RuleLayerInfo`（mrs 格式暂不支持）。层说明按 interval：每小时 / 每天 / 每周 / 每月 / 手动更新。订阅变化后过期层自动删除。iOS：导入/更新订阅后后台刷新到期规则集（`refreshRuleProviders(force:)`）。GEOIP / GEOSITE 规则行暂不编译（mihomo 路由不受影响）。

### 14.v GEOSITE / GEOIP 层（2026-11-08，只追加）
- 规则页在规则集层之后追加订阅里 `GEOSITE,<code>,<policy>` / `GEOIP,<code>,<policy>` 对应的层，名称 `geosite:<code>` / `geoip:<code>`（小写），说明「规则集 · 每周更新」。
- core：`geoSources(nowMillis) -> [GeoSource{kind: geosite|geoip, url, path, codes, due}]`。url 取订阅 `geox-url`（仅 https），否则 MetaCubeX meta-rules-dat latest。任一分类未编译或最旧一层满 7 天即 due。
- 平台把 dat 下载到 `path`（失败不覆盖旧文件），再调 `compileGeo(kind, nowMillis) -> UInt32`（编译的层数）。核心只读映射 dat，只抽取用到的分类；Regex 域名跳过；带 reverse_match 的 geoip 分类跳过。
- 层序号接在规则集之后；订阅变化时与规则集一起清理过期层。
- iOS：`refreshRuleProviders` 末尾自动执行。Android：导入/更新订阅后同样调用 geoSources → 下载 → compileGeo。

### 14.u 未连接时的测速（2026-11-08，只追加）
- 隧道已连接：照旧 `latencyTestBatch` → 扩展/服务内 `zm_url_test` → `recordUrlTest`（经代理的真实 URL 测试）。
- 隧道未连接：`tcpPingTargets(ids ≤ 512) -> [TcpTarget{id, host, port}]`，平台在 App 进程内并发（建议 32）测 TCP 握手，超时 3 s 记 -1，用 `recordLatencies` 写回并推 latencyUpdates。host 不脱敏，仅进程内使用、不展示。基于 UDP 的协议（hysteria/hysteria2/hy2/tuic/wireguard/wg）不返回目标，保持「未测」（UI 在 testLatency 返回后把没有结果的节点退回未测）。握手名额进程级共享。
- 两种结果写入同一延迟缓存，最新一次覆盖；握手时间不含代理协议开销，UI 不区分。

### 14.t 规则页层名与原型对齐（2026-11-09，只追加）
- 第 1 层：名称「Zephyr 覆写」，说明「在订阅之上」（此前说明为「订阅更新时保留」）。
- 第 2 层：名称为生效订阅的名称（如「Nebula Cloud」），说明「订阅规则」，kind = subscription（此前名称与说明对调）。订阅名为空时名称回退为「订阅规则」。平台识别订阅层应看 kind，不看名称。
- 已有安装在下次导入/更新/删除订阅（或场景变更重建覆写层）时自然更新为新文案。

## 15. v0.3 追加（2026-11-14 02:50，core-mobile 已实现，只追加）：导入载荷 / 桌面"同步到手机"二维码
回应 iOS REVIEW-Q2 X-P1-11。§7 `ImportSource.qr / clipboard` 的 payload 不再由平台各自猜，统一交给核心解析：
```
enum ImportPayloadKind { zephyr, clashInstall, url }
record ImportItem { name: String?, url: String, autoUpdateHours: Int32? }   // url 为完整 http(s) 链接（未脱敏，只在内存里交给拉取）
record ImportPayload { kind: ImportPayloadKind, items: [ImportItem] }       // 1 ≤ items ≤ 20
parseImportPayload(payload: String) throws -> ImportPayload                 // 顶层函数（非 MobileCore 方法），纯解析不联网
```
接受的形态（scheme/host 大小写不敏感，载荷 ≤ 4096 字节）：
1. **桌面同步 v1，单条**：`zephyr://import?url=<pct>&name=<pct>&auto=<小时>`；`v` 省略即 1。桌面"同步到手机"默认出这个。
2. **桌面同步 v1，多条**：`zephyr://import?v=1&d=<base64url 无填充(JSON)>`，JSON = `{"v":1,"subs":[{"name":"…","url":"…","auto":12}]}`；`name`、`auto` 可省。
3. **社区通用**：`clash://install-config?url=…&name=…`，`clashmeta://`、`mihomo://` 同。
4. **裸链接**：`http(s)://…`。

校验：url 走桌面 `validate_subscription_url_basic`，name 走 `validate_subscription_name`，auto ∈ [0, 720]。`v` > 1 → `Invalid("导入码版本 vN 过新，请更新 Zephyr")`；其余不识别 → `Invalid`。
平台流程：`parseImportPayload` → 多条时列出确认 → 每条按 §14 拉取 → `importSubscription(item.name ?? "", item.url, fetched, item.autoUpdateHours ?? 默认, …)`。MockEngine 对 `qr/clipboard` 也应先过同一规则（形态 1–4 之外报错）。
桌面端生成二维码的实现不在本仓库（不改 Zephyr 公开仓库）；格式以本节为准，桌面侧按此出码即可。

### 15.a 校验样本（2026-11-14，只追加）
`contract/fixtures/import-payload-v1.json`：§15 四种形态 + 典型拒绝的输入→期望输出（`ok.kind` ∈ `zephyr|clashInstall|url`，`err` ∈ `invalid|subscription_invalid`）。core-mobile `import_payload::tests::fixtures` 逐条比对；两端 MockEngine / UI 预解析（如扫码即时提示）应以同一份样本做单测，保证 Mock 与真核心行为一致。

### 15.b 指令解析样本（2026-11-14，只追加）
回应 Android REVIEW-Q1 H-P1-9。§9 `commandSuggestions` 仍由引擎决定执行什么；输入框下划线与"服务 / 地区 / 范围 / 操作"卡片由平台本地 token 化（iOS `CommandTokenizer`、Android `CommandParser`），两端以原型 `parse()` 为准。
`contract/fixtures/command-parse-v1.json`（`tools/gen-command-parse-fixtures.mjs` 从 `design/prototype/index.html` 直接抽出 `SVC/RGN/ACT/parse()` 生成，`--check` 校验未漂移）：每条 `input` → `service`（显示名）、`scope`（AI|视频|其他）、`region{name,code}`、`action`（直连|4K）、`tokens[{start,len,kind,text}]`（kind ∈ service|region|action，UTF-16 下标）。两端单测应逐条比对。
平台可在样本之外做更严的改进（如两字母码只认独立单词），但样本内条目结果须一致；`视频|流媒体` 的下划线按实际匹配长度（原型固定 2 字为笔误，样本不收录）。

### 15.c 场景漏斗计数（2026-11-14，core-mobile 已实现，只追加）
回应 Android REVIEW-Q1 H-P1-8 / iOS REVIEW-Q1 H-P2-9（场景 sheet 漏斗与"检测自 N 个订阅中的 M 个节点"不能编造）：
```
record NodeFunnel { sourceCount: UInt32, poolSize: UInt64, tested: UInt64, reachable: UInt64, underThreshold: UInt64, thresholdMs: Int32 }
nodeFunnel(nowMillis, maxAgeMillis, thresholdMs) throws -> NodeFunnel   // maxAge ≤ 0 不限新鲜度；thresholdMs ≤ 0 按 300
```
每个节点只看最近一次样本；`tested` 含超时、只数仍在库中的节点；`reachable` = ms ≥ 0；`underThreshold` = 0 ≤ ms < thresholdMs。
建议文案：lede"检测自 {sourceCount} 个订阅中的 {poolSize} 个节点"；漏斗"全部 {poolSize} → 已测速 {tested} → 可连通 {reachable} → 延迟低于 {thresholdMs} ms {underThreshold}"，新鲜度与场景候选一致用 24 h。
原型里"可访问 GPT / 可访问 GPT、Claude 和 Gemini"需要逐节点按服务探测，核心不做（§14.z 只探测场景出口），平台不显示这两级。Mock：sourceCount / poolSize 取原型 lede（2 / 512），其余按 mock 延迟表现算，不另编数字。

### 15.d 扫描目标与扫描进度（2026-11-14，core-mobile 已实现，只追加）
回应 Android REVIEW-Q1 H-P1-12 / iOS H-P1-5 的 `scan: ScanProgress?`（原型 10“正在检测 138/512”+ 行内进度条）。测速由平台驱动（§14.w / §14.u），所以进度是**平台本地状态**，核心只负责选出"这一轮该测哪些"：
```
scanTargets(query, limit, nowMillis, maxAgeMillis) throws -> [UInt64]   // limit ≤ 512（一批 latencyTestBatch）
struct ScanProgress { done: Int, total: Int }                            // 平台本地，不过 FFI
```
- 顺序：查询结果中从未测过的在前（按结果集顺序），再按上次测速时间从旧到新；maxAge 内已测的不返回；maxAge ≤ 0 时只返回从未测过的。只看结果集前 65536 个节点。
- query 同 queryNodes（场景重测用地区代码，如 "JP"；全库用空串）。
- 平台：`total = 返回个数`；按 64 个一组走 latencyTestBatch → zm_url_test → recordUrlTest（未连接时 tcpPingTargets → recordLatencies），每组回来 `done += 本组个数` 并刷新行内进度；`done == total` 或取消时清空 `scan`。返回空数组 = 无需扫描，不显示进度。
- 文案：“正在检测 {done}/{total}”。Mock：按 mock-v0 节点数给 total，done 定时递增即可。

### 15.e 测速有效期与场景重测查询（2026-11-15，core-mobile 已实现，只追加）
回应 iOS（看板 #1）“`scene_api` FRESH_MS 写死 24 h，不跟 `latencyTtlHours`”与“§15.d 场景重测的 query 怎么定”。
```
setLatencyTtlHours(hours: UInt32)      // 0 = 恢复默认 24；进程内有效，平台启动时与设置变更时调用
latencyTtlHours() -> UInt32
record Scene { …, scanQuery: String }  // 追加字段
```
- 有效期影响：`sceneCandidates`、`applySceneChange` 的组内热备、场景自动选点（auto 场景换最快）、`Scene.available`（“n 个可用”）。节点页 / `fastestNodes` / `nodeFunnel` / `scanTargets` 仍由调用方传 `maxAgeMillis`，平台传同一个设置值即可两边一致。
- `Scene.scanQuery`：当前节点所在地区（与 `available`、`sceneCandidates(region = nil)` 同一查询）；未选节点时为空串（全库）。场景重测：`scanTargets(scene.scanQuery, 512, now, ttl)`。
- Mock：`scanQuery` 取所选节点地区，`latencyTtlHours` 记在内存即可。

### 15.f 其余 UniFFI 导出（2026-11-15，补记已有实现，只追加）
以下导出早已存在但契约未列出；`tools/check-contract-exports.mjs`（CI contract job）此后要求每个 `#[uniffi::export]` 方法都在本文出现。
```
// 节点库（一般无需直接调用：importSubscription / updateSubscription / deleteSubscription 已自动重建）
rebuildNodes(sources: [SubscriptionSource]) throws -> BuildReport
rebuildNodesWithProgress(sources, progress: BuildProgress) throws -> BuildReport   // 回调返回 false 取消，旧库不变
rebuildFromSubscriptions(progress?) throws -> BuildReport                            // 由已保存的全部订阅正文重建（启动修复用）
rebuildMockNodes(scale: Double) throws -> BuildReport                                // 开发/演示：原型生成器建库，1.0 = 13,109,802 个
rebuildMockNodesWithProgress(scale, progress) throws -> BuildReport
// 规则层（§14.t / §14.v 的底层；平台一般只用 syncSubscriptionRules 之外的高层接口）
compileRuleLayer(index: UInt32, name, kind: LayerKind, note, defaultPolicy, text) throws -> RuleLayerInfo
loadRules(finalPolicy: String) throws -> RuleStats                                   // 按文件名序重载 rules/ 全部层
syncSubscriptionRules() throws                                                       // 生效订阅的 rules → 第 2 层"订阅规则"，随后热加载
// 链接探针
coreGreeting() -> String                                                             // zephyr-core 版本，确认链接正常
```

### 15.g UniFFI 生成类型名对照（2026-11-15，补记已有实现，只追加）
核心导出的类型名以生成绑定为准；下表是契约早期名与生成名的对照，平台已按右列使用，接口语义不变。`tools/check-contract-exports.mjs` 同时校验每个 `uniffi::Record / Enum / Object / Error` 与回调接口的类型名都在本文出现。
```
契约早期名                 → 生成类型名
ZephyrError { code, message } → MobileError（枚举：Io / Invalid / Corrupt / NotFound / RuleInputInvalid / SubscriptionInvalid /
                                StaleToken / SubscriptionNotFound / SceneNotFound / NotRunning / Cancelled，平台映射到 §10 ErrorCode）
DnsSettings                → DnsConfig { fakeIp, nameservers, fallback, ipv6 }
TunStack                   → TunStackKind { system, gvisor, mixed }
SceneException             → SceneExceptionView { appId, app, node: NodeRow? }

// 未在前文展开的已有类型
enum BuildPhase { parse, index, write }                       // BuildProgress.onProgress 的 phase；parse 阶段 total = 0 表示未知
record NodeDiff { added: UInt64, removed: UInt64, kept: UInt64 }   // BuildReport 内与旧库的差异
enum GeoKind { geosite, geoip }                               // §14.v compileGeo(kind, nowMillis)
record GroupMember { name, proxyType, latencyMs: Int32? }     // groupMembers；-1 = 超时，null = 未测
record HostActivity { host, scene?, node, connections: Int32, totalBytes: Int64, lastSeenAt: Int64 }   // recentHosts
record HostTrace { host, lastSeenAt, connections, totalBytes, rule, chain: [String], scene?, node }    // hostTrace；chain 自顶层组到出口节点
```

### 15.h 场景节点过滤：视频只用 4K 节点（2026-11-15，core-mobile 已实现，只追加）
原型指令“视频只用 4K 节点”（index.html 1046–1055：“视频仅使用 4K 节点 · 22 个中 14 个支持 4K”）。看板 #1 上 Android / iOS 均同意，本节合并两端意见。
```
enum SceneNodeFilter { uhd }                     // 允许值只此一个；以后加 streaming 等再追加枚举项。null = 不过滤
record NodeRow { …, uhd: Bool }                  // 追加字段
record Scene   { …, nodeFilter: SceneNodeFilter? }   // 追加字段，随现有 scenes() 刷新推送
record NodeFilterPreview {
  matching: UInt32,          // 候选中满足过滤的个数（“14 个支持 4K”）
  total: UInt32,             // 不加过滤时的候选个数（“22 个中”），与 Scene.available 同口径
  poolMatching: UInt64,      // 当前地区节点库中满足过滤的个数（不看测速）；0 = 根本没有 4K 节点
  currentKept: Bool,         // 当前节点满足过滤，或场景尚未选节点
  suggested: NodeRow?,       // currentKept=false 时：满足过滤的最快候选；没有已测候选时为 null
  change: ExitChange?        // = previewSceneChange(sceneId, suggested.id)，出口 IP from → to（toIp 恒 null，同 §14）
}
previewSceneNodeFilter(sceneId: String, filter: SceneNodeFilter, nowMillis: Int64) throws -> NodeFilterPreview   // 新鲜度同 setLatencyTtlHours
setSceneNodeFilter(sceneId: String, filter: SceneNodeFilter?) throws    // 持久化
```
- 4K 判定：节点名含 `4K` / `UHD` / `8K`（不区分大小写，同 subscription.rs 名字推断）；以后订阅有显式标签时优先读标签，名字推断作回退。
  - 共享样本 `contract/fixtures/uhd-names-v1.json`（`{name, uhd}`，core-mobile `uhd_fixtures` 单测逐条比对）：仅 ASCII 不区分大小写，全角 `４Ｋ`、开尔文符号 U+212A（`4K`）、分隔开的 `4 K` 不算（2026-11-16 补第 19 例，iOS #170 提出）。两端 Mock 的名字判定应逐条比对。
- 过滤生效范围：该场景的 `sceneCandidates`、`Scene.available`、`applySceneChange` 组内热备、auto 场景换最快。`nodeFunnel` / `fastestNodes` / `scanTargets` 不带场景，不受影响。
- **不主动切走当前节点**（同 §14.y）：`setSceneNodeFilter` 只改之后的候选与自动选点。当前节点不满足时由平台用 preview 的 `suggested` + `change` 出“更改出口 IP？”确认卡，用户确认后照常 `applySceneChange(sceneId, suggested.id)`。
- `poolMatching == 0` 时 `setSceneNodeFilter(…, uhd)` 抛 `MobileError.Invalid`，场景不变。平台应先 preview：`poolMatching == 0` 禁用该指令并提示“没有支持 4K 的节点”；`matching == 0 && poolMatching > 0` 表示有 4K 节点但还没测速，可提示先重测（`scanTargets(scene.scanQuery, …)`）。
- 传 `null` 清除过滤，总是成功。未知 sceneId 抛 `SceneNotFound`。
- 文案建议：“视频仅使用 4K 节点 · {total} 个中 {matching} 个支持 4K”；currentKept 时补“当前节点保持不变”。
- Mock：`uhd` 按名字判定；preview 按 mock 候选算，`change` 复用 previewSceneChange 的 mock。

## 16. v0.4 追加（2026-11-18，发版审计 #209 契约补定义，只追加）
来源：发版前审计（`docs/audit/`，#206）引擎 E01–E47、UI U1–U35 中归 A 的契约缺口。决策规则：原型定义了的照原型；原型没定义的，取对用户更安全的行为并写明理由。本节优先于 §0–§15 中与之冲突的旧描述（旧描述保留不删）。

### 16.a 网络与路由（E10 / E04 / E11 / E18 / E01 / E03）

**① 局域网绕过（E10，两端共同行为，用户不可关）**
隧道的路由表**必须排除**以下网段，这些地址的流量走系统网络、不进 TUN（规则/全局/直连三种模式都一样）：
```
IPv4：10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32
IPv6：fe80::/10, fc00::/7, ff00::/8（::1 本就不进 TUN）
```
- 理由：全局模式下打印机、投屏、NAS、路由器后台若被代理，要么不可达，要么把局域网请求发给远端节点（隐私问题）。iOS 现状已如此（`TunnelNetworkSettingsFactory`）。
- **不排除** fake-ip 段 198.18.0.0/16（DNS 劫持与 fake-ip 依赖它进 TUN），也不排除 100.64.0.0/10（运营商 NAT 段，可能是公网服务）。
- iOS：`NEIPv4Settings.excludedRoutes` / `NEIPv6Settings.excludedRoutes`（现状保持）。
- Android：API 33+ 用 `VpnService.Builder.excludeRoute(IpPrefix)`；API < 33 用 `addRoute` 加补集路由（0.0.0.0/0 减去上表；v6 同理，仅在 IPv6 开启时）。补集由平台本地算好写成常量表并加单测。
- 核心不额外前插 `IP-CIDR,…,DIRECT` 规则：路由层排除已覆盖三种模式，规则层前插只对规则模式有效，还会改变规则页的匹配结果。

**② 底层网络与计费属性（E04）**
- VPN 的计费属性**必须**跟随底层网络：蜂窝 = 计费，Wi‑Fi 按系统判断。其他 App（和 WorkManager 的 `UNMETERED` 约束、本 App 的「仅在 Wi‑Fi 下…」判断）读到的必须是真实值。
- Android：删除 `setMetered(false)`（保持默认 true，即"任一底层网络计费则 VPN 计费"），并用 `ConnectivityManager.NetworkCallback` 跟踪默认网络，调用 `setUnderlyingNetworks(arrayOf(当前默认网络))`；默认网络消失时传 `null`。
- iOS：NE 由系统沿用底层网络属性，无需处理。
- 平台判断"当前是否计费 / 是否 Wi‑Fi"时看**底层网络**（Android `NetworkCapabilities` of 底层网络，或 VPN 网络的 `NET_CAPABILITY_NOT_METERED`——前提是上面已修好；iOS `NWPathMonitor` 的 `isExpensive` / `isConstrained` / `usesInterfaceType(.wifi)`）。

**③ 网络切换后的统一动作（E04）**
默认底层网络变化（Wi‑Fi ↔ 蜂窝、换了 SSID；不含同一网络上的短暂重连 / iOS `reasserting`）后，平台在隧道运行时：
1. 去抖 2 s 后调用一次 `closeAll`（旧接口上的连接已失效，关掉让 App 立刻重连，而不是挂到超时）；
2. 重新评估受信任 Wi‑Fi（见 ⑤）；
3. 场景故障探测的下一轮立即执行（iOS 仅在前台时，见 §16.f）。
不重载配置、不重建 TUN。

**④ IPv6（E11，平台差异登记）**
`TunSettings.ipv6 = false` 的语义是"IPv6 流量被阻断，不得绕过隧道直连"。两端实现不同、结果相同，均保留：
- iOS：始终把 `::/0` 路由进隧道（防泄露），IPv6 关闭时由 mihomo 丢弃；
- Android：IPv6 关闭时不添加 v6 地址/路由，按 `VpnService.Builder` 文档该地址族被系统阻断。不得调用 `allowFamily(AF_INET6)`。

**⑤ 按需连接 / 受信任的 Wi‑Fi（E01，两端语义）**
字段：`onDemand`、`trustedWifi: [String]`（SSID 列表）、`disconnectOnTrusted`。默认值见 §16.c。
- 生效前提：用户**至少手动连接过一次**（首次连接时才会请求 VPN 授权；在此之前按需连接不做任何事，也不弹授权）。
- **用户手动断开 = 暂停按需连接**，直到用户下次手动连接（含小组件 / 控制中心 / 快捷开关 / 通知的"断开"）。否则用户无法断开（E02）。
- 受信任 Wi‑Fi：`disconnectOnTrusted && 当前 SSID ∈ trustedWifi` 时断开隧道；离开该网络且 `onDemand` 开启、且未处于"手动断开暂停"时自动重连。`trustedWifi` 为空时无任何效果。
- iOS：`NEOnDemandRuleDisconnect(ssidMatch: trustedWifi)`（仅当 disconnectOnTrusted）+ 末尾 `NEOnDemandRuleConnect`；手动断开前先 `isOnDemandEnabled = false` 并保存，手动连接时恢复。读 SSID 不需要定位权限。
- Android（没有系统级按需规则，平台自己实现）：
  - `onDemand` = **自动重连**：用户连接后，若 VPN 服务被系统杀掉 / 进程重启 / 设备重启，且上次状态是"已连接且非手动断开"，则自动重新连接（`START_STICKY` + `RECEIVE_BOOT_COMPLETED` 接收器；若不实现开机重连就删掉该权限）。网络从无到有时同样重连。
  - 受信任 Wi‑Fi：前台服务里用 `NetworkCallback` 监听 Wi‑Fi，读 SSID（Android 10+ 需要 `ACCESS_FINE_LOCATION` 且系统定位开关打开；`NEARBY_WIFI_DEVICES` 不能代替）。**拿不到 SSID 时一律按"不受信任"处理**（保持连接——宁可多保护，不可误断），设置页该行显示"需要定位权限才能识别 Wi‑Fi 名称"并提供授权入口；只在用户打开受信任 Wi‑Fi 页时请求权限，不在启动时请求。
  - 系统"始终开启的 VPN"已启用（API 29+ `VpnService.isAlwaysOn()`）时：受信任 Wi‑Fi **不自动断开**（锁定模式下断开会断网），该行显示"由系统『始终开启的 VPN』管理"。
- 两端都不得在用户未操作时首次弹出 VPN 授权。

**⑥ 常开 / Kill switch（E03，平台差异登记）**
- Android：由系统设置"始终开启的 VPN / 屏蔽未使用 VPN 的连接"提供，App 不自行实现；资料库可提供跳转系统 VPN 设置的入口。
- iOS：v1 **不**开 `includeAllNetworks` / `enforceRoutes`（会让 ① 的局域网排除失效，并影响 AirDrop / CarPlay 等本地功能）。v1 不承诺 Kill switch。

**⑦ `strictRoute`（E18）**
核心运行配置固定 `auto-route: false`（路由由系统 VPN 框架设置），mihomo 的 `strict-route` 只在 auto-route 下生效，因此 `TunSettings.strictRoute` **在移动端无效**。字段保留（只追加不改名，旧数据可解码），默认值不变；平台**不得**在 UI 展示该开关。防泄露由 ① 路由排除 + ④ IPv6 阻断保证。

### 16.b 错误码映射（E07 / E43 / E27）

**① 核心 `MobileError` → §10 `ErrorCode` 权威映射表**。先看"调用处覆盖"，没有覆盖的用默认列。两端各加一个表驱动单测逐行比对本表。

| MobileError | 默认 ErrorCode | 调用处覆盖 |
|---|---|---|
| `Io` | `internal` | 消息含 `os error 28` / `No space left` / `ENOSPC` → `storage_full`（任何调用） |
| `Invalid` | `internal` | `parseImportPayload` / `importSubscription` / `previewSubscriptionUpdate` / `updateSubscription` → `subscription_invalid`；`testRule` / `overrideHost` / `connectionTrace` 的 host 输入 → `rule_input_invalid`；`setSceneNodeFilter(…, uhd)` → `rule_input_invalid`（UI 应先 preview，见 §15.h，正常不会走到） |
| `Corrupt` | `internal` | 启动时 `nodeIndex` / `ruleStats` 遇到 → 平台先自动 `rebuildFromSubscriptions` 一次，仍失败才报 `internal` |
| `NotFound` | `internal` | `node` / `nodeDetail` / `sceneCandidates` 里的节点 → `node_not_found`；`groupMembers` / `selectInGroup` / `testGroup` → `group_not_found`；`hostTrace` / `connectionTrace` → `node_not_found`（§13 已定）；"节点库未建立" → `subscription_not_found`（还没有订阅） |
| `RuleInputInvalid` | `rule_input_invalid` | — |
| `SubscriptionInvalid` | `subscription_invalid` | — |
| `StaleToken` | `stale_token` | 平台按 §5 用原查询重查一次；重查仍失败报 `stale_token`（**不是** `internal`），UI 不提示，回到列表顶部 |
| `SubscriptionNotFound` | `subscription_not_found` | — |
| `SceneNotFound` | `scene_not_found` | —（覆写、例外、场景节点过滤等所有带 sceneId 的调用都一样） |
| `NotRunning` | `not_running` | — |
| `Cancelled` | `cancelled` | UI 不提示 |

- 平台自身的错误：VPN 授权被用户拒绝 → `vpn_permission_denied`（**只有**这一种；iOS `startVPNTunnel` / 保存配置的其他失败 → `internal`，扩展启动失败按扩展写回的 errorCode）；拉取订阅见 §16.i；离线（无可用网络）→ `network_unavailable`。
- `message` 只进日志，UI 一律按 code 本地化（§0.5）；任何把 `message` 原文显示给用户的地方都按缺陷处理（U27）。

**② 没有订阅时连接（E07）**
- 引擎 `connect()` 在订阅列表为空时抛 **`subscription_not_found`**（不再用 `subscription_invalid`：用户没有订阅，不是订阅坏了）。
- UI：订阅为空时首页大开关不发起连接，直接打开导入面板；小组件 / 控制中心 / 快捷开关 / 快捷指令触发时收到 `subscription_not_found`，打开 App 到导入面板（无法打开时显示"还没有订阅"）。
- §14.x 扩展找不到 `file-descriptor: -1` 哨兵（有订阅但配置文件缺失/损坏）仍是 `subscription_invalid`。

**③ 重载失败（E27）**
需要重载的操作（`applySceneChange` 返回 needsReload、`setGlobalNode`、`overrideHost`、`setSceneException`、`setSceneSource` 的 auto 换点、订阅更新、设置热应用）按下表处理：

| 隧道状态 | 行为 |
|---|---|
| 未运行 / 已断开 | 只改核心状态，不重载；下次连接时生成的配置自然包含改动。操作成功。 |
| 连接中 | 排队，连上后补一次重载（多次合并为一次）。操作成功。 |
| 已连接，写配置或 `zm_reload` 失败 | **回滚**核心里的改动（场景：`applySceneChange(sceneId, previous)`；覆写：恢复原 `hostOverride`；例外：恢复原节点或 null；全局节点：恢复原节点），然后抛错：写配置失败按 ① 的 `Io` 规则（多为 `storage_full` / `internal`），`zm_reload` 失败 → `core_crashed`。UI 显示"未能应用更改"，不显示"已切换"。 |

理由：不回滚时 UI 显示新节点、实际流量仍走旧配置，用户看到的和实际不一致；不报错（静默吞掉）同样如此。不新增错误码，沿用 `core_crashed`，免得两端 14 种语言再加文案。

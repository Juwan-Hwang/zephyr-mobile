// 领域模型 —— 与 contract/zephyr-engine.md v0 逐项一致。
// 全部是值类型：public、Sendable、Hashable、Codable（App Group 共享给小组件 / 实时活动）。
// 字段名照抄契约（lowerCamelCase）；序列化名用契约的 snake_case（CodingKeys）。
// 时间 = 毫秒 Unix 时间戳 Int64；速率 = 字节/秒 Int64；流量 = 字节 Int64；延迟 = 毫秒 Int32（nil 未测，-1 超时）。

import Foundation

/// 节点 ID。核心：server+port+protocol 指纹；Mock：`region * 100_000_000 + index`。同一订阅内跨更新稳定。
public typealias NodeId = UInt64

// MARK: - §10 错误

public enum ErrorCode: String, Sendable, Hashable, Codable, CaseIterable {
    case notRunning = "not_running"
    case vpnPermissionDenied = "vpn_permission_denied"
    case networkUnavailable = "network_unavailable"
    case subscriptionInvalid = "subscription_invalid"
    case subscriptionFetchFailed = "subscription_fetch_failed"
    case nodeNotFound = "node_not_found"
    case sceneNotFound = "scene_not_found"
    case groupNotFound = "group_not_found"
    case ruleInputInvalid = "rule_input_invalid"
    case coreCrashed = "core_crashed"
    case storageFull = "storage_full"
    case cancelled
    case `internal`
}

/// 引擎统一错误。文案不由引擎给，UI 按 `code` 本地化；`message` 只用于日志。
public struct ZephyrError: Error, Sendable, Hashable, Codable, CustomStringConvertible {
    public var code: ErrorCode
    public var message: String
    public init(code: ErrorCode, message: String = "") { self.code = code; self.message = message }
    public var description: String { "ZephyrError(\(code.rawValue)): \(message)" }
}

// MARK: - §1 连接与模式

public enum ConnectionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case disconnected, connecting, connected, disconnecting, failed
}

public enum ProxyMode: String, Sendable, Hashable, Codable, CaseIterable {
    case rule, global, direct
}

public enum NetworkKind: String, Sendable, Hashable, Codable, CaseIterable {
    case wifi, cellular, ethernet, other
}

public struct NetworkInfo: Sendable, Hashable, Codable {
    public var kind: NetworkKind
    public var name: String?
    public var trusted: Bool
    public init(kind: NetworkKind, name: String? = nil, trusted: Bool = false) {
        self.kind = kind; self.name = name; self.trusted = trusted
    }
}

public struct ConnectionState: Sendable, Hashable, Codable {
    public var status: ConnectionStatus
    public var mode: ProxyMode
    /// 进入 connected 的时间（ms）。
    public var since: Int64?
    /// mode == global 时的出口。
    public var globalNodeId: NodeId?
    public var network: NetworkInfo?
    /// status == failed 时。
    public var error: ZephyrError?

    public init(status: ConnectionStatus, mode: ProxyMode, since: Int64? = nil, globalNodeId: NodeId? = nil,
                network: NetworkInfo? = nil, error: ZephyrError? = nil) {
        self.status = status; self.mode = mode; self.since = since
        self.globalNodeId = globalNodeId; self.network = network; self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case status, mode, since, network, error
        case globalNodeId = "global_node_id"
    }
}

// MARK: - §2 流量与用量

public struct TrafficSample: Sendable, Hashable, Codable {
    public var at: Int64
    public var upBps: Int64
    public var downBps: Int64
    public init(at: Int64, upBps: Int64, downBps: Int64) { self.at = at; self.upBps = upBps; self.downBps = downBps }
    enum CodingKeys: String, CodingKey { case at; case upBps = "up_bps"; case downBps = "down_bps" }
}

public struct UsageSummary: Sendable, Hashable, Codable {
    public var todayBytes: Int64
    /// "4 个地区"
    public var regionsToday: Int32
    /// "6 小时在线"
    public var onlineMillisToday: Int64
    /// "38 ms 最快"
    public var fastestLatencyMs: Int32?
    /// 24 个，今日每小时字节。
    public var hourly: [Int64]
    public init(todayBytes: Int64, regionsToday: Int32, onlineMillisToday: Int64, fastestLatencyMs: Int32?, hourly: [Int64]) {
        self.todayBytes = todayBytes; self.regionsToday = regionsToday; self.onlineMillisToday = onlineMillisToday
        self.fastestLatencyMs = fastestLatencyMs; self.hourly = hourly
    }
    enum CodingKeys: String, CodingKey {
        case todayBytes = "today_bytes", regionsToday = "regions_today", onlineMillisToday = "online_millis_today"
        case fastestLatencyMs = "fastest_latency_ms", hourly
    }
}

// MARK: - §3 场景

public enum SceneKind: String, Sendable, Hashable, Codable, CaseIterable {
    case ai, video, other, custom
}

public enum SceneSource: String, Sendable, Hashable, Codable, CaseIterable {
    case auto, manual
    case subscriptionGroup = "subscription_group"
}

public struct SceneException: Sendable, Hashable, Codable {
    public var app: String
    public var node: NodeSummary
    public init(app: String, node: NodeSummary) { self.app = app; self.node = node }
}

public struct Scene: Sendable, Hashable, Codable, Identifiable {
    /// "ai" | "video" | "other" | 自定义 uuid
    public var id: String
    public var kind: SceneKind
    public var name: String
    public var available: Int32
    public var selected: NodeSummary
    public var exitIp: String?
    public var source: SceneSource
    public var testedAt: Int64?
    public var note: String?
    public var exceptions: [SceneException]

    public init(id: String, kind: SceneKind, name: String, available: Int32, selected: NodeSummary, exitIp: String? = nil,
                source: SceneSource, testedAt: Int64? = nil, note: String? = nil, exceptions: [SceneException] = []) {
        self.id = id; self.kind = kind; self.name = name; self.available = available; self.selected = selected
        self.exitIp = exitIp; self.source = source; self.testedAt = testedAt; self.note = note; self.exceptions = exceptions
    }
    enum CodingKeys: String, CodingKey {
        case id, kind, name, available, selected, source, note, exceptions
        case exitIp = "exit_ip", testedAt = "tested_at"
    }
}

/// "更改出口 IP？"确认弹层。
public struct ExitChange: Sendable, Hashable, Codable {
    /// nil = 全局
    public var sceneId: String?
    public var fromRegion: String
    public var fromIp: String?
    public var toRegion: String
    public var toIp: String?
    public var affectedApps: [String]
    public var unchangedApps: [String]
    public init(sceneId: String?, fromRegion: String, fromIp: String?, toRegion: String, toIp: String?,
                affectedApps: [String] = [], unchangedApps: [String] = []) {
        self.sceneId = sceneId; self.fromRegion = fromRegion; self.fromIp = fromIp; self.toRegion = toRegion
        self.toIp = toIp; self.affectedApps = affectedApps; self.unchangedApps = unchangedApps
    }
    enum CodingKeys: String, CodingKey {
        case sceneId = "scene_id", fromRegion = "from_region", fromIp = "from_ip", toRegion = "to_region"
        case toIp = "to_ip", affectedApps = "affected_apps", unchangedApps = "unchanged_apps"
    }
}

// MARK: - §4 策略组

public enum GroupType: String, Sendable, Hashable, Codable, CaseIterable {
    case select
    case urlTest = "url_test"
    case fallback
    case loadBalance = "load_balance"
    case relay
}

public struct PolicyGroup: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    public var type: GroupType
    public var selected: String?
    public var memberCount: Int32
    public var testedAt: Int64?
    public var id: String { name }
    public init(name: String, type: GroupType, selected: String? = nil, memberCount: Int32, testedAt: Int64? = nil) {
        self.name = name; self.type = type; self.selected = selected; self.memberCount = memberCount; self.testedAt = testedAt
    }
    enum CodingKeys: String, CodingKey {
        case name, type, selected
        case memberCount = "member_count", testedAt = "tested_at"
    }
}

// MARK: - §5 节点库

public struct NodeSummary: Sendable, Hashable, Codable, Identifiable {
    public var id: NodeId
    /// "东京 NTT IPLC 03 ×1.5"
    public var name: String
    /// ISO 3166 alpha-2，"JP"
    public var region: String
    public var city: String?
    public var carrier: String?
    /// IPLC|IEPL|BGP|家宽|原生
    public var tag: String?
    /// VLESS|Hy2|TUIC|SS|Trojan
    public var `protocol`: String
    public var multiplier: Float?
    /// 只给缓存值。nil = 未测/过期，-1 = 超时。
    public var latencyMs: Int32?

    public init(id: NodeId, name: String, region: String, city: String? = nil, carrier: String? = nil, tag: String? = nil,
                protocol: String, multiplier: Float? = nil, latencyMs: Int32? = nil) {
        self.id = id; self.name = name; self.region = region; self.city = city; self.carrier = carrier
        self.tag = tag; self.protocol = `protocol`; self.multiplier = multiplier; self.latencyMs = latencyMs
    }
    enum CodingKeys: String, CodingKey {
        case id, name, region, city, carrier, tag, `protocol`, multiplier
        case latencyMs = "latency_ms"
    }
}

/// `rowOffset` 是该分区头行在虚拟列表里的行号（含之前所有分区头）。
public struct RegionSection: Sendable, Hashable, Codable, Identifiable {
    public var region: String
    public var name: String
    public var count: Int64
    public var rowOffset: Int64
    public var id: String { region }
    public init(region: String, name: String, count: Int64, rowOffset: Int64) {
        self.region = region; self.name = name; self.count = count; self.rowOffset = rowOffset
    }
    enum CodingKeys: String, CodingKey { case region, name, count; case rowOffset = "row_offset" }
}

public struct NodeIndex: Sendable, Hashable, Codable {
    public var total: Int64
    public var sections: [RegionSection]
    public var testedCount: Int64
    public init(total: Int64, sections: [RegionSection], testedCount: Int64) {
        self.total = total; self.sections = sections; self.testedCount = testedCount
    }
    enum CodingKeys: String, CodingKey { case total, sections; case testedCount = "tested_count" }
}

public struct NodeQueryResult: Sendable, Hashable, Codable {
    public var query: String
    public var total: Int64
    /// 只含命中的分区，rowOffset 按结果重排。
    public var sections: [RegionSection]
    public var highlights: [String]
    public var tookMicros: Int64
    /// 结果句柄，配合 nodeRows 分页。
    public var token: Int64
    public init(query: String, total: Int64, sections: [RegionSection], highlights: [String], tookMicros: Int64, token: Int64) {
        self.query = query; self.total = total; self.sections = sections; self.highlights = highlights
        self.tookMicros = tookMicros; self.token = token
    }
    enum CodingKeys: String, CodingKey {
        case query, total, sections, highlights, token
        case tookMicros = "took_micros"
    }
}

public struct NodePage: Sendable, Hashable, Codable {
    public var rows: [NodeSummary]
    public var offset: Int64
    public var total: Int64
    public init(rows: [NodeSummary], offset: Int64, total: Int64) { self.rows = rows; self.offset = offset; self.total = total }
}

public struct LatencyUpdate: Sendable, Hashable, Codable {
    public var id: NodeId
    public var latencyMs: Int32
    public var at: Int64
    public init(id: NodeId, latencyMs: Int32, at: Int64) { self.id = id; self.latencyMs = latencyMs; self.at = at }
    enum CodingKeys: String, CodingKey { case id, at; case latencyMs = "latency_ms" }
}

public struct NodeDetail: Sendable, Hashable, Codable {
    public var summary: NodeSummary
    /// 已脱敏
    public var server: String
    public var port: Int32
    public var subscription: String
    public var extra: [String: String]
    public init(summary: NodeSummary, server: String, port: Int32, subscription: String, extra: [String: String] = [:]) {
        self.summary = summary; self.server = server; self.port = port; self.subscription = subscription; self.extra = extra
    }
}

// MARK: - §6 规则

public enum LayerKind: String, Sendable, Hashable, Codable, CaseIterable {
    case override, subscription, domain, ip
}

public struct RuleLayer: Sendable, Hashable, Codable, Identifiable {
    public var index: Int32
    public var kind: LayerKind
    public var name: String
    public var count: Int64
    public var note: String
    public var updatedAt: Int64?
    public var id: Int32 { index }
    public init(index: Int32, kind: LayerKind, name: String, count: Int64, note: String, updatedAt: Int64? = nil) {
        self.index = index; self.kind = kind; self.name = name; self.count = count; self.note = note; self.updatedAt = updatedAt
    }
    enum CodingKeys: String, CodingKey { case index, kind, name, count, note; case updatedAt = "updated_at" }
}

public struct RuleStats: Sendable, Hashable, Codable {
    public var total: Int64
    public var layers: [RuleLayer]
    public var compiled: Bool
    public var diskBytes: Int64
    public init(total: Int64, layers: [RuleLayer], compiled: Bool, diskBytes: Int64) {
        self.total = total; self.layers = layers; self.compiled = compiled; self.diskBytes = diskBytes
    }
    enum CodingKeys: String, CodingKey { case total, layers, compiled; case diskBytes = "disk_bytes" }
}

public struct RuleTrace: Sendable, Hashable, Codable {
    public var input: String
    public var isIp: Bool
    /// nil = 落到 MATCH（第 layers.count+1 层"其余流量"）
    public var layerIndex: Int32?
    /// "DOMAIN-SUFFIX,github.com" | "MATCH"
    public var rule: String
    /// 该层内序号，"#41"
    public var ruleNo: Int64?
    /// "DIRECT" | "REJECT" | 场景 id
    public var policy: String
    public var scene: Scene?
    public var exitIp: String?
    public var tookMicros: Int64
    public init(input: String, isIp: Bool, layerIndex: Int32?, rule: String, ruleNo: Int64?, policy: String,
                scene: Scene? = nil, exitIp: String? = nil, tookMicros: Int64) {
        self.input = input; self.isIp = isIp; self.layerIndex = layerIndex; self.rule = rule; self.ruleNo = ruleNo
        self.policy = policy; self.scene = scene; self.exitIp = exitIp; self.tookMicros = tookMicros
    }
    enum CodingKeys: String, CodingKey {
        case input, rule, policy, scene
        case isIp = "is_ip", layerIndex = "layer_index", ruleNo = "rule_no", exitIp = "exit_ip", tookMicros = "took_micros"
    }
}

// MARK: - §7 订阅与配置

public struct SubscriptionDiff: Sendable, Hashable, Codable {
    public var addedNodes: Int64
    public var removedNodes: Int64
    public var ruleChanges: Int64
    public var overridesKept: Bool
    public var scenesRetested: Bool
    public init(addedNodes: Int64, removedNodes: Int64, ruleChanges: Int64, overridesKept: Bool, scenesRetested: Bool) {
        self.addedNodes = addedNodes; self.removedNodes = removedNodes; self.ruleChanges = ruleChanges
        self.overridesKept = overridesKept; self.scenesRetested = scenesRetested
    }
    enum CodingKeys: String, CodingKey {
        case addedNodes = "added_nodes", removedNodes = "removed_nodes", ruleChanges = "rule_changes"
        case overridesKept = "overrides_kept", scenesRetested = "scenes_retested"
    }
}

public struct Subscription: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    /// 已脱敏
    public var url: String?
    public var nodeCount: Int64
    public var usedBytes: Int64?
    public var totalBytes: Int64?
    public var remainingBytes: Int64?
    public var expiresAt: Int64?
    public var updatedAt: Int64?
    public var autoUpdateHours: Int32
    public var lastDiff: SubscriptionDiff?
    public init(id: String, name: String, url: String? = nil, nodeCount: Int64, usedBytes: Int64? = nil, totalBytes: Int64? = nil,
                remainingBytes: Int64? = nil, expiresAt: Int64? = nil, updatedAt: Int64? = nil, autoUpdateHours: Int32,
                lastDiff: SubscriptionDiff? = nil) {
        self.id = id; self.name = name; self.url = url; self.nodeCount = nodeCount; self.usedBytes = usedBytes
        self.totalBytes = totalBytes; self.remainingBytes = remainingBytes; self.expiresAt = expiresAt
        self.updatedAt = updatedAt; self.autoUpdateHours = autoUpdateHours; self.lastDiff = lastDiff
    }
    enum CodingKeys: String, CodingKey {
        case id, name, url
        case nodeCount = "node_count", usedBytes = "used_bytes", totalBytes = "total_bytes"
        case remainingBytes = "remaining_bytes", expiresAt = "expires_at", updatedAt = "updated_at"
        case autoUpdateHours = "auto_update_hours", lastDiff = "last_diff"
    }
}

/// 契约 §7 `subscriptionsSummary()` 的返回 `{ count, totalNodes }`。
public struct SubscriptionsSummary: Sendable, Hashable, Codable {
    public var count: Int32
    public var totalNodes: Int64
    public init(count: Int32, totalNodes: Int64) { self.count = count; self.totalNodes = totalNodes }
    enum CodingKeys: String, CodingKey { case count; case totalNodes = "total_nodes" }
}

public enum ImportSource: String, Sendable, Hashable, Codable, CaseIterable {
    case url, clipboard, qr, file
}

// MARK: - §8 连接、日志、设置

public struct ConnectionInfo: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var host: String
    public var app: String?
    public var scene: String?
    public var node: String
    public var upBytes: Int64
    public var downBytes: Int64
    public var startedAt: Int64
    public init(id: String, host: String, app: String? = nil, scene: String? = nil, node: String,
                upBytes: Int64, downBytes: Int64, startedAt: Int64) {
        self.id = id; self.host = host; self.app = app; self.scene = scene; self.node = node
        self.upBytes = upBytes; self.downBytes = downBytes; self.startedAt = startedAt
    }
    enum CodingKeys: String, CodingKey {
        case id, host, app, scene, node
        case upBytes = "up_bytes", downBytes = "down_bytes", startedAt = "started_at"
    }
}

public enum LogLevel: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case debug, info, warning, error
    var rank: Int { switch self { case .debug: 0; case .info: 1; case .warning: 2; case .error: 3 } }
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rank < b.rank }
}

public struct LogLine: Sendable, Hashable, Codable {
    public var at: Int64
    public var level: LogLevel
    public var message: String
    public init(at: Int64, level: LogLevel, message: String) { self.at = at; self.level = level; self.message = message }
}

public enum Accent: String, Sendable, Hashable, Codable, CaseIterable {
    case blue, green, orange, pink
}

public enum Appearance: String, Sendable, Hashable, Codable, CaseIterable {
    case system, dark, light
}

/// 契约 v0 未展开 DnsSettings 的字段；此处为 K 的最小定义（只追加，不改名）。
public struct DnsSettings: Sendable, Hashable, Codable {
    /// mihomo enhanced-mode：fake-ip
    public var fakeIp: Bool
    public var nameservers: [String]
    public var fallback: [String]
    public var ipv6: Bool
    public init(fakeIp: Bool = true, nameservers: [String] = ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"],
                fallback: [String] = ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"], ipv6: Bool = false) {
        self.fakeIp = fakeIp; self.nameservers = nameservers; self.fallback = fallback; self.ipv6 = ipv6
    }
    enum CodingKeys: String, CodingKey { case nameservers, fallback, ipv6; case fakeIp = "fake_ip" }
}

public enum TunStack: String, Sendable, Hashable, Codable, CaseIterable {
    case system, gvisor, mixed
}

/// 契约 v0 未展开 TunSettings 的字段；此处为 K 的最小定义。
public struct TunSettings: Sendable, Hashable, Codable {
    public var stack: TunStack
    public var mtu: Int32
    public var ipv6: Bool
    public var strictRoute: Bool
    public init(stack: TunStack = .system, mtu: Int32 = 9000, ipv6: Bool = false, strictRoute: Bool = true) {
        self.stack = stack; self.mtu = mtu; self.ipv6 = ipv6; self.strictRoute = strictRoute
    }
    enum CodingKeys: String, CodingKey { case stack, mtu, ipv6; case strictRoute = "strict_route" }
}

public struct Settings: Sendable, Hashable, Codable {
    public var onDemand: Bool
    public var trustedWifi: [String]
    public var disconnectOnTrusted: Bool
    public var localProxyPort: Int32
    public var localProxyAuth: Bool
    public var testOnWifiOnly: Bool
    public var latencyTtlHours: Int32
    public var autoUpdateHours: Int32
    public var updateOnWifiOnly: Bool
    public var showChangesBeforeUpdate: Bool
    public var dns: DnsSettings
    public var tun: TunSettings
    public var accent: Accent
    public var appearance: Appearance
    /// "图案由今天的流量生成，不含节点名称与 IP"
    public var shareAnonymousPattern: Bool

    public init(onDemand: Bool, trustedWifi: [String], disconnectOnTrusted: Bool, localProxyPort: Int32, localProxyAuth: Bool,
                testOnWifiOnly: Bool, latencyTtlHours: Int32, autoUpdateHours: Int32, updateOnWifiOnly: Bool,
                showChangesBeforeUpdate: Bool, dns: DnsSettings, tun: TunSettings, accent: Accent, appearance: Appearance,
                shareAnonymousPattern: Bool) {
        self.onDemand = onDemand; self.trustedWifi = trustedWifi; self.disconnectOnTrusted = disconnectOnTrusted
        self.localProxyPort = localProxyPort; self.localProxyAuth = localProxyAuth; self.testOnWifiOnly = testOnWifiOnly
        self.latencyTtlHours = latencyTtlHours; self.autoUpdateHours = autoUpdateHours; self.updateOnWifiOnly = updateOnWifiOnly
        self.showChangesBeforeUpdate = showChangesBeforeUpdate; self.dns = dns; self.tun = tun; self.accent = accent
        self.appearance = appearance; self.shareAnonymousPattern = shareAnonymousPattern
    }
    enum CodingKeys: String, CodingKey {
        case dns, tun, accent, appearance
        case onDemand = "on_demand", trustedWifi = "trusted_wifi", disconnectOnTrusted = "disconnect_on_trusted"
        case localProxyPort = "local_proxy_port", localProxyAuth = "local_proxy_auth", testOnWifiOnly = "test_on_wifi_only"
        case latencyTtlHours = "latency_ttl_hours", autoUpdateHours = "auto_update_hours", updateOnWifiOnly = "update_on_wifi_only"
        case showChangesBeforeUpdate = "show_changes_before_update", shareAnonymousPattern = "share_anonymous_pattern"
    }
}

/// 契约 §8 `storage()` 的返回 `{ nodesBytes, rulesBytes, freeBytes }`。
public struct StorageInfo: Sendable, Hashable, Codable {
    public var nodesBytes: Int64
    public var rulesBytes: Int64
    public var freeBytes: Int64
    public init(nodesBytes: Int64, rulesBytes: Int64, freeBytes: Int64) {
        self.nodesBytes = nodesBytes; self.rulesBytes = rulesBytes; self.freeBytes = freeBytes
    }
    enum CodingKeys: String, CodingKey { case nodesBytes = "nodes_bytes", rulesBytes = "rules_bytes", freeBytes = "free_bytes" }
}

// MARK: - §9 命令搜索

public enum CommandKind: String, Sendable, Hashable, Codable, CaseIterable {
    case switchNode = "switch_node"
    case switchMode = "switch_mode"
    case openNodeQuery = "open_node_query"
    case testRule = "test_rule"
    case openPage = "open_page"
    case toggleConnection = "toggle_connection"
}

public struct CommandSuggestion: Sendable, Hashable, Codable {
    public var kind: CommandKind
    public var title: String
    public var subtitle: String?
    public var payload: String
    public init(kind: CommandKind, title: String, subtitle: String? = nil, payload: String) {
        self.kind = kind; self.title = title; self.subtitle = subtitle; self.payload = payload
    }
}

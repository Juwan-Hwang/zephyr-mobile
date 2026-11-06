// 领域模型。全部是值类型、Sendable、Hashable、Codable（便于 App Group 共享给小组件 / 实时活动）。

import Foundation

// MARK: - 连接

public enum ProxyMode: String, Sendable, Hashable, Codable, CaseIterable {
    case rule, global, direct
    public var title: String {
        switch self { case .rule: "规则"; case .global: "全局"; case .direct: "直连" }
    }
}

public enum ConnectionPhase: String, Sendable, Hashable, Codable {
    case disconnected, connecting, connected, disconnecting, failed
}

public struct ConnectionState: Sendable, Hashable, Codable {
    public var phase: ConnectionPhase
    public var mode: ProxyMode
    /// 本次连接开始时间（connected 时有值）。UI 自己用 TimelineView 算时长。
    public var since: Date?
    /// failed 时给用户看的原因（已本地化）。
    public var failureReason: String?
    /// 全局模式下的出口节点（首页“全局模式”卡片）。
    public var globalNode: NodeBrief?

    public init(phase: ConnectionPhase, mode: ProxyMode, since: Date? = nil, failureReason: String? = nil, globalNode: NodeBrief? = nil) {
        self.phase = phase; self.mode = mode; self.since = since; self.failureReason = failureReason; self.globalNode = globalNode
    }
    public static let idle = ConnectionState(phase: .disconnected, mode: .rule)
    public var isOn: Bool { phase == .connected || phase == .connecting }
}

// MARK: - 流量

public struct TrafficSample: Sendable, Hashable, Codable {
    public var time: Date
    /// 字节/秒
    public var down: Double
    public var up: Double
    public init(time: Date, down: Double, up: Double) { self.time = time; self.down = down; self.up = up }
}

public struct DailyUsage: Sendable, Hashable, Codable {
    public var date: Date
    public var bytes: Int64
    public var regions: Int
    public var hoursOnline: Int
    public var fastestLatencyMs: Int
    /// 24 个小时桶的用量（字节），给小组件柱状图与今日卡片纹理用。
    public var hourly: [Int64]
    public init(date: Date, bytes: Int64, regions: Int, hoursOnline: Int, fastestLatencyMs: Int, hourly: [Int64]) {
        self.date = date; self.bytes = bytes; self.regions = regions; self.hoursOnline = hoursOnline
        self.fastestLatencyMs = fastestLatencyMs; self.hourly = hourly
    }
}

// MARK: - 节点

/// 节点 ID：地区序号 + 地区内序号（原型的 r*1e8+j）。真实核心里是 server+port+protocol 指纹的 64 位哈希。
public struct NodeID: Sendable, Hashable, Codable, CustomStringConvertible {
    public var raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
    public var description: String { String(raw) }
}

public enum NodeProtocol: String, Sendable, Hashable, Codable, CaseIterable {
    case vless = "VLESS", hysteria2 = "Hy2", tuic = "TUIC", shadowsocks = "SS", trojan = "Trojan"
}

/// 地区码（ISO 3166-1 alpha-2，大写）。
public struct RegionCode: Sendable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var code: String
    public init(_ code: String) { self.code = code.uppercased() }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { code }
}

public struct NodeBrief: Sendable, Hashable, Codable, Identifiable {
    public var id: NodeID
    public var name: String
    public var region: RegionCode
    public init(id: NodeID, name: String, region: RegionCode) { self.id = id; self.name = name; self.region = region }
}

public struct Node: Sendable, Hashable, Codable, Identifiable {
    public var id: NodeID
    public var name: String
    public var region: RegionCode
    public var proto: NodeProtocol
    /// 计费倍率（×1.5 等）；1 表示不显示。
    public var multiplier: Double
    public init(id: NodeID, name: String, region: RegionCode, proto: NodeProtocol, multiplier: Double = 1) {
        self.id = id; self.name = name; self.region = region; self.proto = proto; self.multiplier = multiplier
    }
    public var brief: NodeBrief { NodeBrief(id: id, name: name, region: region) }
}

public enum Latency: Sendable, Hashable, Codable {
    case ms(Int)
    case timeout
    case testing
    public var millis: Int? { if case .ms(let v) = self { v } else { nil } }
}

public struct RegionBucket: Sendable, Hashable, Codable, Identifiable {
    public var region: RegionCode
    public var nameZh: String
    public var count: Int
    public var id: RegionCode { region }
    public init(region: RegionCode, nameZh: String, count: Int) { self.region = region; self.nameZh = nameZh; self.count = count }
}

public struct NodeLibrarySummary: Sendable, Hashable, Codable {
    public var total: Int
    public var subscriptionCount: Int
    public var regions: [RegionBucket]
    public var testedCount: Int
    public init(total: Int, subscriptionCount: Int, regions: [RegionBucket], testedCount: Int) {
        self.total = total; self.subscriptionCount = subscriptionCount; self.regions = regions; self.testedCount = testedCount
    }
}

public struct NodeQuery: Sendable, Hashable, Codable {
    /// 自由文本：地区 / 城市 / 线路（运营商）/ 标签（IPLC…），空格分隔取交集。
    public var text: String
    public var region: RegionCode?
    public var hideTimeouts: Bool
    public init(text: String = "", region: RegionCode? = nil, hideTimeouts: Bool = false) {
        self.text = text; self.region = region; self.hideTimeouts = hideTimeouts
    }
}

/// 一次查询的结果句柄。行数可达 1e8，UI 只按窗口读。
public struct NodeResultSet: Sendable, Hashable {
    public var token: UInt64
    /// 总行数（含地区头行）
    public var rowCount: Int
    /// 节点数（不含头行）
    public var nodeCount: Int
    /// 各分段（地区）的起始行与节点数，给右侧索引条和置顶头用。
    public var sections: [Section]
    /// 需要高亮的词（搜索命中的城市 / 线路等）
    public var highlights: [String]
    /// 查询耗时（毫秒），页面上显示“n 个 · 0.4 ms”
    public var elapsedMs: Double

    public struct Section: Sendable, Hashable {
        public var region: RegionCode
        public var nameZh: String
        public var firstRow: Int
        public var nodeCount: Int
        public init(region: RegionCode, nameZh: String, firstRow: Int, nodeCount: Int) {
            self.region = region; self.nameZh = nameZh; self.firstRow = firstRow; self.nodeCount = nodeCount
        }
    }
    public init(token: UInt64, rowCount: Int, nodeCount: Int, sections: [Section], highlights: [String], elapsedMs: Double) {
        self.token = token; self.rowCount = rowCount; self.nodeCount = nodeCount; self.sections = sections
        self.highlights = highlights; self.elapsedMs = elapsedMs
    }
    /// 二分找某行所属分段。
    public func sectionIndex(forRow row: Int) -> Int {
        var lo = 0, hi = sections.count - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if sections[m].firstRow <= row { lo = m } else { hi = m - 1 } }
        return max(0, lo)
    }
    /// 某行（节点行）在全部结果中的 1 基序号，用于“n / total”。
    public func ordinal(ofRow row: Int) -> Int {
        let si = sectionIndex(forRow: row)
        var before = 0
        for i in 0..<si { before += sections[i].nodeCount }
        return before + max(0, row - sections[si].firstRow)
    }
}

public enum NodeListRow: Sendable, Hashable {
    case header(NodeResultSet.Section)
    case node(Node)
}

// MARK: - 场景

public enum SceneStrategy: String, Sendable, Hashable, Codable, CaseIterable {
    /// 订阅分组：直接用订阅提供的分组
    case subscriptionGroup
    /// Zephyr 优选：在场景池里按可达性 + 延迟选
    case zephyrPick
    public var title: String { self == .subscriptionGroup ? "订阅分组" : "Zephyr 优选" }
}

public struct Scene: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String
    public var id: ID
    public var title: String            // AI / 视频 / 其他
    public var availableCount: Int
    public var subtitle: String         // “9 个可用” / “订阅分组” / “Claude 不可用”
    public var subtitleIsWarning: Bool
    public var current: NodeBrief?
    /// 右侧第二行：“Netflix 完整片库”、“Claude：US-Fixed-01”（带锁）
    public var note: String?
    public var noteIsPinned: Bool
    /// 正在检测：进度（0…1）与文案
    public var probing: Probing?
    public var strategy: SceneStrategy

    public struct Probing: Sendable, Hashable, Codable {
        public var tested: Int
        public var total: Int
        public init(tested: Int, total: Int) { self.tested = tested; self.total = total }
    }

    public init(id: ID, title: String, availableCount: Int, subtitle: String, subtitleIsWarning: Bool = false,
                current: NodeBrief?, note: String? = nil, noteIsPinned: Bool = false, probing: Probing? = nil,
                strategy: SceneStrategy) {
        self.id = id; self.title = title; self.availableCount = availableCount; self.subtitle = subtitle
        self.subtitleIsWarning = subtitleIsWarning; self.current = current; self.note = note
        self.noteIsPinned = noteIsPinned; self.probing = probing; self.strategy = strategy
    }
}

public struct SceneDetail: Sendable, Hashable, Codable {
    public var scene: Scene
    public var poolSize: Int            // 检测自 … 个节点
    public var poolSubscriptions: Int   // … 个订阅
    /// 漏斗：512 全部 → 138 延迟低于 300ms → 27 可访问 GPT → 9 全部可访问
    public var funnel: [FunnelStep]
    public var candidates: [Candidate]

    public struct FunnelStep: Sendable, Hashable, Codable {
        public var count: Int
        public var label: String
        public init(count: Int, label: String) { self.count = count; self.label = label }
    }
    public struct Candidate: Sendable, Hashable, Codable, Identifiable {
        public var node: NodeBrief
        public var latencyMs: Int
        public var pinnedFor: String?   // “Claude 固定”
        public var isSelected: Bool
        public var id: NodeID { node.id }
        public init(node: NodeBrief, latencyMs: Int, pinnedFor: String? = nil, isSelected: Bool = false) {
            self.node = node; self.latencyMs = latencyMs; self.pinnedFor = pinnedFor; self.isSelected = isSelected
        }
    }
    public init(scene: Scene, poolSize: Int, poolSubscriptions: Int, funnel: [FunnelStep], candidates: [Candidate]) {
        self.scene = scene; self.poolSize = poolSize; self.poolSubscriptions = poolSubscriptions
        self.funnel = funnel; self.candidates = candidates
    }
}

// MARK: - 规则

public enum RuleLayerKind: String, Sendable, Hashable, Codable {
    case override = "覆写", subscription = "订阅", domain = "域名", ip = "IP"
}

public struct RuleLayer: Sendable, Hashable, Codable, Identifiable {
    public var index: Int          // 1 基匹配顺序
    public var title: String
    public var detail: String      // “规则集 · 每天更新”
    public var kind: RuleLayerKind
    public var count: Int
    public var id: Int { index }
    public init(index: Int, title: String, detail: String, kind: RuleLayerKind, count: Int) {
        self.index = index; self.title = title; self.detail = detail; self.kind = kind; self.count = count
    }
}

public struct RuleLibrarySummary: Sendable, Hashable, Codable {
    public var total: Int
    public var layers: [RuleLayer]
    public var compiled: Bool
    public var diskBytes: Int64
    public init(total: Int, layers: [RuleLayer], compiled: Bool, diskBytes: Int64) {
        self.total = total; self.layers = layers; self.compiled = compiled; self.diskBytes = diskBytes
    }
}

public enum RuleOutcome: Sendable, Hashable, Codable {
    case direct
    case rejected
    case proxied(scene: String, node: NodeBrief, exitIP: String)
}

public struct RuleTrace: Sendable, Hashable, Codable {
    public var input: String
    /// 命中的层（nil = 其余流量 MATCH）
    public var layerIndex: Int?
    public var layerTitle: String
    public var rule: String          // “DOMAIN-SUFFIX,openai.com”
    public var ruleOrdinal: Int?     // #41
    public var outcome: RuleOutcome
    public var elapsedMs: Double
    public init(input: String, layerIndex: Int?, layerTitle: String, rule: String, ruleOrdinal: Int?, outcome: RuleOutcome, elapsedMs: Double) {
        self.input = input; self.layerIndex = layerIndex; self.layerTitle = layerTitle; self.rule = rule
        self.ruleOrdinal = ruleOrdinal; self.outcome = outcome; self.elapsedMs = elapsedMs
    }
}

// MARK: - 订阅

public struct Subscription: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var nodeCount: Int
    public var remainingBytes: Int64?
    public var usedFraction: Double?   // 0…1，用量条
    public var expires: Date?
    public var updatedAt: Date?
    public init(id: ID, name: String, nodeCount: Int, remainingBytes: Int64?, usedFraction: Double?, expires: Date?, updatedAt: Date?) {
        self.id = id; self.name = name; self.nodeCount = nodeCount; self.remainingBytes = remainingBytes
        self.usedFraction = usedFraction; self.expires = expires; self.updatedAt = updatedAt
    }
}

public struct SubscriptionDiff: Sendable, Hashable, Codable {
    public var subscriptionID: Subscription.ID
    public var subscriptionName: String
    public var addedNodes: Int
    public var removedNodes: Int
    public var changedRules: Int
    public var overridesKept: Bool
    public var at: Date
    public init(subscriptionID: Subscription.ID, subscriptionName: String, addedNodes: Int, removedNodes: Int, changedRules: Int, overridesKept: Bool, at: Date) {
        self.subscriptionID = subscriptionID; self.subscriptionName = subscriptionName; self.addedNodes = addedNodes
        self.removedNodes = removedNodes; self.changedRules = changedRules; self.overridesKept = overridesKept; self.at = at
    }
}

public struct SubscriptionSummary: Sendable, Hashable, Codable {
    public var total: Int
    public var updateIntervalHours: Int
    public var featured: [Subscription]   // 卡片里展示的前几个
    public var othersCount: Int
    public var othersNodeCount: Int
    public var lastDiff: SubscriptionDiff?
    public var todayBytes: Int64
    public init(total: Int, updateIntervalHours: Int, featured: [Subscription], othersCount: Int, othersNodeCount: Int, lastDiff: SubscriptionDiff?, todayBytes: Int64) {
        self.total = total; self.updateIntervalHours = updateIntervalHours; self.featured = featured
        self.othersCount = othersCount; self.othersNodeCount = othersNodeCount; self.lastDiff = lastDiff; self.todayBytes = todayBytes
    }
}

public enum ImportSource: Sendable, Hashable, Codable {
    case url(String)
    case qrPayload(String)
    case file(URL)
    case desktopPairing(code: String)
}

// MARK: - 连接记录

public struct ConnectionRecord: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String
    public var id: ID
    public var host: String
    public var sceneTitle: String
    public var nodeName: String?      // nil = 直连
    public var bytes: Int64
    public var lastSeen: Date
    public init(id: ID, host: String, sceneTitle: String, nodeName: String?, bytes: Int64, lastSeen: Date) {
        self.id = id; self.host = host; self.sceneTitle = sceneTitle; self.nodeName = nodeName; self.bytes = bytes; self.lastSeen = lastSeen
    }
}

public struct ConnectionTrace: Sendable, Hashable, Codable {
    public var record: ConnectionRecord
    public var connectionCount: Int
    public var steps: [Step]
    public var override: ConnectionOverride
    public var alwaysApply: Bool

    public struct Step: Sendable, Hashable, Codable {
        public var label: String       // 规则 / 场景 / 节点 / 出口
        public var value: String
        public var detail: String?
        public var isMono: Bool
        public var isTerminal: Bool
        public init(label: String, value: String, detail: String? = nil, isMono: Bool = false, isTerminal: Bool = false) {
            self.label = label; self.value = value; self.detail = detail; self.isMono = isMono; self.isTerminal = isTerminal
        }
    }
    public init(record: ConnectionRecord, connectionCount: Int, steps: [Step], override: ConnectionOverride, alwaysApply: Bool) {
        self.record = record; self.connectionCount = connectionCount; self.steps = steps; self.override = override; self.alwaysApply = alwaysApply
    }
}

public enum ConnectionOverride: String, Sendable, Hashable, Codable, CaseIterable {
    case unchanged, direct, video, other
    public var title: String {
        switch self { case .unchanged: "不变"; case .direct: "直连"; case .video: "视频"; case .other: "其他" }
    }
}

// MARK: - 指令

public struct CommandPlan: Sendable, Hashable, Codable {
    public var input: String
    public var tokens: [Token]
    public var title: String         // “Gemini 使用日本节点”
    public var summary: String       // “3 个可用，将使用东京 03。”
    public var warnings: [String]    // “出口 IP 将更改 …”
    public var footnote: String?
    public var canApply: Bool

    public struct Token: Sendable, Hashable, Codable {
        public var kind: String   // 服务 / 地区 / 范围
        public var value: String
        public init(kind: String, value: String) { self.kind = kind; self.value = value }
    }
    public init(input: String, tokens: [Token], title: String, summary: String, warnings: [String], footnote: String?, canApply: Bool) {
        self.input = input; self.tokens = tokens; self.title = title; self.summary = summary
        self.warnings = warnings; self.footnote = footnote; self.canApply = canApply
    }
}

// MARK: - 设置

public struct EngineSettings: Sendable, Hashable, Codable {
    public var onDemand: Bool
    public var trustedWiFi: [String]
    public var localProxyPortEnabled: Bool
    public var localProxyPort: Int
    public var testOnlyOnWiFi: Bool
    public var resultRetentionHours: Int
    public var autoUpdateHours: Int
    public var updateOnlyOnWiFi: Bool
    public var reviewBeforeUpdate: Bool
    public var usageMode: UsageMode

    public enum UsageMode: String, Sendable, Hashable, Codable { case simple, optimized }

    public init(onDemand: Bool = true, trustedWiFi: [String] = ["家"], localProxyPortEnabled: Bool = false, localProxyPort: Int = 7890,
                testOnlyOnWiFi: Bool = true, resultRetentionHours: Int = 24, autoUpdateHours: Int = 12,
                updateOnlyOnWiFi: Bool = true, reviewBeforeUpdate: Bool = false, usageMode: UsageMode = .optimized) {
        self.onDemand = onDemand; self.trustedWiFi = trustedWiFi; self.localProxyPortEnabled = localProxyPortEnabled
        self.localProxyPort = localProxyPort; self.testOnlyOnWiFi = testOnlyOnWiFi; self.resultRetentionHours = resultRetentionHours
        self.autoUpdateHours = autoUpdateHours; self.updateOnlyOnWiFi = updateOnlyOnWiFi; self.reviewBeforeUpdate = reviewBeforeUpdate
        self.usageMode = usageMode
    }
}

public struct StorageUsage: Sendable, Hashable, Codable {
    public var nodesBytes: Int64
    public var rulesBytes: Int64
    public var availableBytes: Int64
    public init(nodesBytes: Int64, rulesBytes: Int64, availableBytes: Int64) {
        self.nodesBytes = nodesBytes; self.rulesBytes = rulesBytes; self.availableBytes = availableBytes
    }
}

// MARK: - 错误

public enum EngineError: Error, Sendable, Hashable {
    case notFound
    case invalidInput(String)
    case unavailable(String)
    case vpnPermissionDenied
    case staleResultSet
}

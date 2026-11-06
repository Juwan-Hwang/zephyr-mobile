// 固定值 —— contract/mock-spec.md §5–§6 与原型首页 / 场景页 / 订阅页 / 设置页的文案数据。

import Foundation
import ZephyrKit

/// 原型里有名有姓的节点（场景池、全局出口、例外）。ID 落在生成节点范围之外：region * 1e8 + 90,000,000 + k。
struct PinnedNode: Sendable {
    let summary: NodeSummary
    let ip: String
}

enum MockFixtures {

    static func pinnedId(_ region: String, _ k: UInt64) -> NodeId {
        UInt64(MockNodes.regionIndex(code: region)!) * MockNodes.idStride + 90_000_000 + k
    }

    private static func pin(_ region: String, _ k: UInt64, _ name: String, _ ms: Int32, _ ip: String,
                            city: String?, carrier: String?, tag: String?, proto: String, mult: Float? = nil) -> PinnedNode {
        PinnedNode(summary: NodeSummary(id: pinnedId(region, k), name: name, region: region, city: city, carrier: carrier,
                                        tag: tag, protocol: proto, multiplier: mult, latencyMs: ms), ip: ip)
    }

    // 原型 NODES / CPOOL / POOL
    static let hkHKT = pin("HK", 1, "香港 HKT", 38, "203.0.113.24", city: "香港", carrier: "HKT", tag: "IPLC", proto: "VLESS")
    static let hk02 = pin("HK", 2, "香港 02", 44, "198.51.100.52", city: "香港", carrier: "HKBN", tag: "IEPL", proto: "Hy2")
    static let tp02 = pin("TW", 2, "台北 02", 48, "198.51.100.30", city: "台北", carrier: "HiNet", tag: "家宽", proto: "VLESS")
    static let twFixed = pin("TW", 1, "TW-Fixed-01", 52, "198.51.100.41", city: "台北", carrier: "HiNet", tag: "原生", proto: "Trojan")
    static let tk03 = pin("JP", 3, "东京 03", 61, "203.0.113.61", city: "东京", carrier: "NTT", tag: "IPLC", proto: "VLESS", mult: 1.5)
    static let sg02 = pin("SG", 2, "新加坡 02", 74, "198.51.100.7", city: "新加坡", carrier: "SingTel", tag: "IEPL", proto: "Hy2")
    static let tk07 = pin("JP", 7, "东京 07", 83, "203.0.113.70", city: "东京", carrier: "IIJ", tag: "BGP", proto: "TUIC")
    static let sg05 = pin("SG", 5, "新加坡 05", 96, "198.51.100.9", city: "新加坡", carrier: "StarHub", tag: "BGP", proto: "VLESS")
    static let os01 = pin("JP", 11, "大阪 01", 102, "203.0.113.75", city: "大阪", carrier: "KDDI", tag: "家宽", proto: "SS")
    static let la04 = pin("US", 4, "洛杉矶 04", 172, "203.0.113.19", city: "洛杉矶", carrier: "CN2 GIA", tag: "IPLC", proto: "Trojan")
    static let usFixed = pin("US", 1, "US-Fixed-01", 188, "203.0.113.28", city: "洛杉矶", carrier: "Zenlayer", tag: "原生", proto: "VLESS")
    static let ld01 = pin("GB", 1, "伦敦 01", 231, "198.51.100.88", city: "伦敦", carrier: "BT", tag: "BGP", proto: "VLESS")

    static let pinned: [PinnedNode] = [hkHKT, hk02, tp02, twFixed, tk03, sg02, tk07, sg05, os01, la04, usFixed, ld01]
    static let pinnedById: [NodeId: PinnedNode] = Dictionary(uniqueKeysWithValues: pinned.map { ($0.summary.id, $0) })

    /// AI 场景候选池（原型 POOL，9 个可用）。
    static let aiPool: [PinnedNode] = [tp02, tk03, sg02, tk07, sg05, os01, la04, usFixed, ld01]
    /// 视频场景具名候选（原型 CPOOL.视频）；另补香港生成节点凑满 22 个。
    static let videoPinned: [PinnedNode] = [hkHKT, hk02, tk03, sg02, la04]
    static let otherPool: [PinnedNode] = [twFixed, tp02]

    /// 场景内受影响的应用（预览"更改出口 IP？"用）。
    static let sceneApps: [String: [String]] = ["ai": ["GPT", "Gemini", "Claude"], "video": ["Netflix", "YouTube"], "other": []]

    static func initialScenes(now: Int64) -> [Scene] {
        let tested = now - 2 * 3_600_000
        return [
            Scene(id: "ai", kind: .ai, name: "AI", available: 9, selected: sg02.summary, exitIp: sg02.ip, source: .auto,
                  testedAt: tested, note: nil, exceptions: [SceneException(app: "Claude", node: usFixed.summary)]),
            Scene(id: "video", kind: .video, name: "视频", available: 22, selected: hkHKT.summary, exitIp: hkHKT.ip, source: .auto,
                  testedAt: tested, note: "Netflix 完整片库", exceptions: []),
            // 原型显示"—"：订阅分组，可用数未知 → 0（UI 对 subscription_group 显示"—"）。
            Scene(id: "other", kind: .other, name: "其他", available: 0, selected: twFixed.summary, exitIp: twFixed.ip,
                  source: .subscriptionGroup, testedAt: tested, note: nil, exceptions: []),
        ]
    }

    /// 生成节点的 mock 出口 IP（文档地址段，确定性）。
    static func exitIp(for id: NodeId) -> String {
        if let p = pinnedById[id] { return p.ip }
        let h = MockNodes.hsh(5, Int64(id % 4_000_000_000))
        let block = h % 2 == 0 ? "203.0.113" : "198.51.100"
        return "\(block).\(h % 250 + 2)"
    }

    // MARK: 今日

    static let todayBytes: Int64 = 1_800_000_000

    /// 24 项，总和 = 1.8 GB，按 hsh(2,h) 权重分配，余数并入权重最大的小时。
    static let hourly: [Int64] = {
        let w = (0..<24).map { Int64(MockNodes.hsh(2, Int64($0)) % 1000) + 50 }
        let W = w.reduce(0, +)
        var out = w.map { todayBytes * $0 / W }
        let rest = todayBytes - out.reduce(0, +)
        out[w.firstIndex(of: w.max()!)!] += rest
        return out
    }()

    static func usage() -> UsageSummary {
        UsageSummary(todayBytes: todayBytes, regionsToday: 4, onlineMillisToday: 6 * 3_600_000, fastestLatencyMs: 38, hourly: hourly)
    }

    // MARK: 流量

    /// 第 t 秒的确定性样本：down 2.4–3.4 MB/s，up 150–260 KB/s（sin + hsh(1,t) 抖动）。
    static func traffic(second t: Int64, seed: UInt64) -> TrafficSample {
        let tt = t &+ Int64(truncatingIfNeeded: seed)
        let h = MockNodes.hsh(1, tt)
        let down = 2_900_000 + Int64((350_000 * sin(Double(tt) / 7)).rounded()) + Int64(h % 300_001) - 150_000
        let up = 205_000 + Int64((35_000 * sin(Double(tt) / 5)).rounded()) + Int64((h >> 8) % 40_001) - 20_000
        return TrafficSample(at: t * 1000, upBps: up, downBps: down)
    }

    /// 原型首页 9:41 的读数："2.8 MB/s ↓ · 194 KB/s ↑"。
    static func prototypeSample(at ms: Int64) -> TrafficSample { TrafficSample(at: ms, upBps: 194_000, downBps: 2_800_000) }

    // MARK: 订阅

    static let othersCount = 212
    static let othersNodes: Int64 = 13_098_480

    static func initialSubscriptions(now: Int64) -> [Subscription] {
        let day: Int64 = 86_400_000
        var subs: [Subscription] = [
            Subscription(id: "nebula", name: "Nebula Cloud", url: "https://sub.nebula.cloud/api/v1/••••••", nodeCount: 8204,
                         usedBytes: 113_600_000_000, totalBytes: 200_000_000_000, remainingBytes: 86_400_000_000,
                         expiresAt: now + 26 * day + 3 * 3_600_000, updatedAt: now - 2 * 3_600_000, autoUpdateHours: 12,
                         lastDiff: SubscriptionDiff(addedNodes: 1204, removedNodes: 318, ruleChanges: 0, overridesKept: true, scenesRetested: true)),
            Subscription(id: "orbit", name: "Orbit", url: "https://orbit.example/link/••••••", nodeCount: 3118,
                         usedBytes: 88_000_000_000, totalBytes: 100_000_000_000, remainingBytes: 12_000_000_000,
                         expiresAt: now + 3 * day + 4 * 3_600_000, updatedAt: now - 5 * 3_600_000, autoUpdateHours: 12, lastDiff: nil),
        ]
        // 其余 212 个合计 13,098,480：均分后成对 ±d 扰动，总和不变。
        let base = othersNodes / Int64(othersCount), rem = othersNodes % Int64(othersCount)
        var counts = (0..<othersCount).map { base + (Int64($0) < rem ? 1 : 0) }
        for i in 0..<(othersCount / 2) {
            let d = Int64(MockNodes.hsh(4, Int64(i)) % 40_000)
            counts[i] += d; counts[othersCount - 1 - i] -= d
        }
        for i in 0..<othersCount {
            let h = MockNodes.hsh(6, Int64(i))
            let n = i + 3
            subs.append(Subscription(id: "sub-\(n)", name: "订阅 \(n < 10 ? "00" : n < 100 ? "0" : "")\(n)",
                                     url: "https://sub\(n).example/••••••", nodeCount: counts[i],
                                     usedBytes: nil, totalBytes: nil, remainingBytes: nil,
                                     expiresAt: h % 3 == 0 ? nil : now + Int64(10 + h % 300) * day,
                                     updatedAt: now - Int64(h % 12 + 1) * 3_600_000, autoUpdateHours: 12, lastDiff: nil))
        }
        return subs
    }

    static func diff(for id: String, seed: UInt64) -> SubscriptionDiff {
        if id == "nebula" { return SubscriptionDiff(addedNodes: 1204, removedNodes: 318, ruleChanges: 0, overridesKept: true, scenesRetested: true) }
        var acc: Int64 = Int64(truncatingIfNeeded: seed)
        for u in id.unicodeScalars { acc = acc &* 31 &+ Int64(u.value) }
        let h = MockNodes.hsh(8, acc & 0xFFFF_FFFF)
        return SubscriptionDiff(addedNodes: Int64(h % 400), removedNodes: Int64((h >> 9) % 120), ruleChanges: Int64((h >> 18) % 4),
                                overridesKept: true, scenesRetested: h % 2 == 0)
    }

    // MARK: 设置 / 存储

    static let settings = Settings(onDemand: true, trustedWifi: ["家"], disconnectOnTrusted: true, localProxyPort: 7890,
                                   localProxyAuth: false, testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12,
                                   updateOnWifiOnly: true, showChangesBeforeUpdate: true, dns: DnsSettings(), tun: TunSettings(),
                                   accent: .blue, appearance: .system, shareAnonymousPattern: true)

    static let storage = StorageInfo(nodesBytes: 600_000_000, rulesBytes: 1_900_000_000, freeBytes: 3_100_000_000)

    // MARK: 策略组（名字, 类型, 成员查询, 成员数）

    static let groups: [(String, GroupType, String, Int64)] = [
        ("节点选择", .select, "", 2000),
        ("自动选择", .urlTest, "iplc", 500),
        ("故障转移", .fallback, "hkt", 200),
        ("负载均衡", .loadBalance, "jp", 300),
        ("香港", .select, "香港", 1000),
        ("美国", .select, "美国", 1000),
    ]

    // MARK: 活动连接（host, app, sceneId?；nil = 直连）

    static let connectionSeeds: [(String, String?, String?)] = [
        ("chatgpt.com", "ChatGPT", "ai"), ("api.openai.com", "ChatGPT", "ai"), ("claude.ai", "Claude", "ai"),
        ("gemini.google.com", "Gemini", "ai"), ("www.netflix.com", "Netflix", "video"), ("ipv4-c001.nflxvideo.net", "Netflix", "video"),
        ("www.youtube.com", "YouTube", "video"), ("rr3---sn-a5mekn7z.googlevideo.com", "YouTube", "video"),
        ("github.com", "Safari", nil), ("api.github.com", "Xcode", nil), ("www.baidu.com", "Safari", nil),
        ("weibo.com", "微博", nil), ("example.org", "Safari", "other"), ("x.com", "X", "other"),
        ("api.telegram.org", "Telegram", "other"), ("www.reddit.com", "Safari", "other"),
    ]

    static let initialLogs: [(LogLevel, String)] = [
        (.info, "Zephyr 核心已启动 · mihomo"),
        (.info, "已加载 214 个订阅 · 13,109,802 个节点"),
        (.info, "规则已编译 · 7 层 · 103,606,731 条"),
        (.debug, "DNS fake-ip 已就绪"),
        (.warning, "Orbit 剩余流量不足 15%"),
        (.info, "场景已检测：AI · 视频 · 其他"),
    ]
}

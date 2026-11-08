// SharedState —— App 与扩展（小组件 / 实时活动 / 控制中心 / PacketTunnel）之间共享的摘要。
//
// 只放“扫一眼”需要的东西：连接状态、最近速率、今日用量、场景摘要、外观强调色、隧道偏好。
// 不依赖 ZephyrKit（PacketTunnel 不链接 UI 包，保持 NE 50 MB 内存预算），字段全部是基础类型。
// 写入：SharedStore（原子写 + Darwin notify）。读取：SharedStore.read()（损坏/缺失 → .empty）。

import Foundation

struct SharedState: Codable, Sendable, Hashable {
    static let schemaVersion = 1

    var version: Int = SharedState.schemaVersion
    /// 最后一次写入时间。
    var updatedAt: Date
    var connection: Connection
    var rate: Rate
    var usage: Usage
    /// 首页场景卡的摘要（按显示顺序，最多 4 个）。
    var scenes: [SceneSummary]
    /// 强调色：blue | green | orange | pink（与 ZTokens.Accent rawValue 一致）。
    var accent: String
    /// 隧道偏好（App 从引擎 Settings 同步，PacketTunnel 启动时读取）。
    var tunnel: TunnelPreferences

    // MARK: 连接

    enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case disconnected, connecting, connected, disconnecting, failed

        var isOn: Bool { self == .connected || self == .connecting }
        var title: String {
            switch self {
            case .disconnected: "未连接"
            case .connecting: "正在连接"
            case .connected: "已连接"
            case .disconnecting: "正在断开"
            case .failed: "连接失败"
            }
        }
    }

    enum Mode: String, Codable, Sendable, Hashable, CaseIterable {
        case rule, global, direct
        var title: String {
            switch self {
            case .rule: "规则"
            case .global: "全局"
            case .direct: "直连"
            }
        }
    }

    struct Connection: Codable, Sendable, Hashable {
        var status: Status
        var mode: Mode
        /// 进入 connected 的时间。
        var since: Date?
        /// failed 时的 ErrorCode 序列化名（UI 本地化）。
        var errorCode: String?

        var isOn: Bool { status.isOn }
    }

    // MARK: 写入归属

    /// App（SharedStatePublisher）写盘时只合并自己负责的字段，不整份覆盖：
    /// 速率两边都写（扩展每秒、App 节流 5 s），按时间戳新者胜，避免 App 的旧快照把扩展刚写的速率盖掉；
    /// 连接、场景、强调色、用量、隧道偏好由 App 写；bypassLAN 等 App 不认识的字段保留盘上的值。
    mutating func adopt(appSnapshot s: SharedState) {
        connection = s.connection
        if (s.rate.at ?? .distantPast) >= (rate.at ?? .distantPast) { rate = s.rate }
        usage = s.usage
        scenes = s.scenes
        accent = s.accent
        tunnel.mode = s.tunnel.mode
        tunnel.mtu = s.tunnel.mtu
        tunnel.ipv6 = s.tunnel.ipv6
    }

    // MARK: 速率 / 用量

    struct Rate: Codable, Sendable, Hashable {
        var downBps: Int64
        var upBps: Int64
        var at: Date?
        /// 最近若干秒的下行速率（字节/秒），给小组件 / 实时活动画迷你曲线；最多 `capacity` 个。
        var recentDown: [Int64]

        static let capacity = 30

        mutating func push(down: Int64, up: Int64, at date: Date) {
            downBps = down; upBps = up; at = date
            recentDown.append(down)
            if recentDown.count > Self.capacity { recentDown.removeFirst(recentDown.count - Self.capacity) }
        }
    }

    struct Usage: Codable, Sendable, Hashable {
        /// 统计日（当地 0 点）。
        var day: Date
        var todayBytes: Int64
        /// 24 个小时桶（字节）。
        var hourly: [Int64]
        var regionsToday: Int
        var fastestLatencyMs: Int?
    }

    // MARK: 场景

    struct SceneSummary: Codable, Sendable, Hashable, Identifiable {
        /// "ai" | "video" | "other" | uuid
        var id: String
        /// "AI" / "视频" / "其他"
        var name: String
        /// ISO 3166 alpha-2，"JP"
        var region: String
        /// 当前出口节点显示名，"东京 03"
        var nodeName: String
        /// 缓存延迟；nil 未测，-1 超时。
        var latencyMs: Int?
    }

    // MARK: 隧道偏好

    struct TunnelPreferences: Codable, Sendable, Hashable {
        var mode: Mode = .rule
        var mtu: Int = TunnelPreferences.defaultMTU
        var ipv6: Bool = false
        /// 绕过局域网（excludedRoutes 加 RFC1918 / 链路本地）。
        var bypassLAN: Bool = true

        /// NE 内存预算下的折中：比 1500 吞吐高、比 mihomo 默认 9000 的单包缓冲小。
        static let defaultMTU = 4064
    }
}

// MARK: - 预置值

extension SharedState {
    /// 冷启动 / 读取失败时的空状态。
    static var empty: SharedState {
        SharedState(
            updatedAt: Date(timeIntervalSince1970: 0),
            connection: Connection(status: .disconnected, mode: .rule, since: nil, errorCode: nil),
            rate: Rate(downBps: 0, upBps: 0, at: nil, recentDown: []),
            usage: Usage(day: Calendar.current.startOfDay(for: Date()), todayBytes: 0,
                         hourly: Array(repeating: 0, count: 24), regionsToday: 0, fastestLatencyMs: nil),
            scenes: [],
            accent: "blue",
            tunnel: TunnelPreferences()
        )
    }

    /// 小组件图库 / 占位 / 快照：取原型截图（shots/hs.png、shots/lock.png）里的值。
    static func prototype(now: Date = Date()) -> SharedState {
        // 原型柱状图的相对高度；按比例分配 1.8 GB。
        let weights: [Int64] = [22, 14, 10, 6, 8, 30, 52, 74, 58, 40, 62, 80, 64, 44, 78, 96, 88, 104, 62, 50, 40, 60, 82, 120]
        let total = weights.reduce(0, +)
        let hourly = weights.map { $0 * 1_800_000_000 / total }
        return SharedState(
            updatedAt: now,
            connection: Connection(status: .connected, mode: .rule,
                                   since: now.addingTimeInterval(-(2 * 3600 + 14 * 60 + 7)), errorCode: nil),
            rate: Rate(downBps: 2_800_000, upBps: 194_000, at: now,
                       recentDown: [2_400_000, 2_600_000, 3_100_000, 2_900_000, 2_700_000, 3_300_000, 2_800_000]),
            usage: Usage(day: Calendar.current.startOfDay(for: now), todayBytes: 1_800_000_000,
                         hourly: hourly, regionsToday: 4, fastestLatencyMs: 38),
            scenes: [
                SceneSummary(id: "ai", name: "AI", region: "JP", nodeName: "东京 03", latencyMs: 61),
                SceneSummary(id: "video", name: "视频", region: "HK", nodeName: "香港 HKT", latencyMs: 38),
                SceneSummary(id: "other", name: "其他", region: "TW", nodeName: "TW-Fixed-01", latencyMs: 48),
            ],
            accent: "blue",
            tunnel: TunnelPreferences()
        )
    }

    /// 今日用量属于“今天”吗？跨天后小组件显示 0。
    func usage(on date: Date, calendar: Calendar = .current) -> Usage {
        if calendar.isDate(usage.day, inSameDayAs: date) { return usage }
        return Usage(day: calendar.startOfDay(for: date), todayBytes: 0,
                     hourly: Array(repeating: 0, count: 24), regionsToday: 0, fastestLatencyMs: nil)
    }
}

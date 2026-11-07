// 今日用量账本（契约 §2 usageToday）：只由 PacketTunnel 写（随 1 Hz 采样、每 5 s 落盘），App 只读。
// 单独一个小文件（App Group/core/usage.json），不放进 SharedState，避免 App 侧整份写回 SharedState 时覆盖扩展的累计值。
//
// mihomo 的 upTotal/downTotal 是进程内累计，扩展重启归零：`counterTotal` 记录上一次读数，差值计入当前小时；
// 读数变小（重启）时把新读数整份计入。在线时长按两次采样间隔累加（单次最多 10 s，防止睡眠/挂起后一次记太多）。

import Foundation

struct UsageLedger: Codable, Sendable, Hashable {
    /// 统计日（当地 0 点）
    var day: Date
    var hourly: [Int64]
    var onlineMillis: Int64
    var counterTotal: Int64?
    var lastTick: Date?

    static let maxTickGap: TimeInterval = 10

    static func empty(_ now: Date, calendar: Calendar = .current) -> UsageLedger {
        UsageLedger(day: calendar.startOfDay(for: now), hourly: Array(repeating: 0, count: 24), onlineMillis: 0, counterTotal: nil, lastTick: nil)
    }

    var todayBytes: Int64 { hourly.reduce(0, +) }

    /// 扩展（重新）启动：mihomo 计数器归零，丢掉旧读数与采样点。
    mutating func tunnelStarted() {
        counterTotal = nil
        lastTick = nil
    }

    mutating func record(total: Int64, at now: Date, calendar: Calendar = .current) {
        if !calendar.isDate(day, inSameDayAs: now) {
            day = calendar.startOfDay(for: now)
            hourly = Array(repeating: 0, count: 24)
            onlineMillis = 0
            lastTick = nil
        }
        let delta: Int64
        if let prev = counterTotal { delta = total >= prev ? total - prev : total } else { delta = total }
        let hour = calendar.component(.hour, from: now)
        if hourly.count != 24 { hourly = Array(repeating: 0, count: 24) }
        hourly[min(max(hour, 0), 23)] += max(delta, 0)
        counterTotal = total
        if let t = lastTick {
            let gap = min(max(now.timeIntervalSince(t), 0), Self.maxTickGap)
            onlineMillis += Int64(gap * 1000)
        }
        lastTick = now
    }

    /// 读取时跨天视为 0。
    func today(_ now: Date, calendar: Calendar = .current) -> UsageLedger {
        calendar.isDate(day, inSameDayAs: now) ? self : .empty(now, calendar: calendar)
    }

    // MARK: 落盘

    static var url: URL { AppGroup.coreDirectory.appendingPathComponent("usage.json") }

    static func load(from url: URL = UsageLedger.url) -> UsageLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageLedger.self, from: data)
    }

    func save(to url: URL = UsageLedger.url) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

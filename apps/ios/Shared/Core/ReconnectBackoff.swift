// ReconnectBackoff —— 起不来的内核不能被按需连接无限次拉起（#1 A 真机结论 7152702939 ②；与 Android ReconnectBackoff 同构）。
//
// iOS 上“自动连接”来自系统按需规则（NEOnDemandRuleConnect）：每次触发都会拉起扩展跑一遍 startTunnel。
//   - `geodata missing:`、订阅缺失 / 无效：重试也是同一个结果 → 直接暂停按需，直到用户下次手动连接（与手动断开同一个暂停）。
//   - 其他 core_crashed：退避 30 s → 2 min → 10 min；连续 3 次失败后暂停到下次手动连接。
//   - 其他错误（虚拟网卡 / 网络）：不退避，按需照旧。
// 尝试在 zm_start 之前就计数（App Group 里同步写），扩展在启动中途被 jetsam 杀掉也算一次，系统再拉起时照样按退避等待。
//
// 扩展进程不能改系统 VPN 配置（NETunnelProviderManager 只属于 App）：扩展在 startTunnel 入口按本类型拒绝退避期 / 已暂停时的
// 自动启动（不碰内核、不联网），并写下暂停标记；App 运行时（启动、隧道状态变化）据此把系统的 isOnDemandEnabled 关掉
// （TunnelController.disarmOnDemandIfPaused），之后系统就不再触发。手动连接（App / 小组件 / 控制中心 / 快捷指令都经
// TunnelController，startVPNTunnel 带 `manualStartOption`）清零。
//
// 冷启动“网络回归即重连”：iOS 没有 App 侧的网络回归逻辑（由系统按需规则负责）；扩展里的 NetworkChangeDetector 首个快照只作基线。

import Foundation

enum ReconnectBackoff {
    /// 第 1、2、3 次连续失败后的等待；第 3 次即暂停。
    static let delays: [TimeInterval] = [30, 120, 600]
    static let maxFailures = 3
    static let geodataMissingPrefix = "geodata missing:"
    /// TunnelController 手动启动时放进 startVPNTunnel(options:) 的键；系统按需 / 系统设置里的开关启动时没有。
    static let manualStartOption = "com.juwanh.zephyr.manual"

    struct Outcome: Equatable, Sendable {
        /// 暂停按需连接，直到下次手动连接。
        var pause: Bool
        /// 下次自动尝试最早在多少秒后；nil = 不安排退避（pause 或非内核错误）。
        var retryAfter: TimeInterval?
    }

    static func isGeodataMissing(_ message: String?) -> Bool {
        guard let m = message?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return m.range(of: geodataMissingPrefix, options: [.caseInsensitive, .anchored]) != nil
    }

    /// 一次失败之后怎么办。`failures` = 含本次在内的连续失败次数（≥ 1）。`code` 为契约 §10 ErrorCode 序列化名。
    static func onFailure(code: String, message: String?, failures: Int) -> Outcome {
        switch code {
        case "subscription_invalid", "subscription_not_found":
            return Outcome(pause: true, retryAfter: nil)
        case "core_crashed":
            if isGeodataMissing(message) || failures >= maxFailures { return Outcome(pause: true, retryAfter: nil) }
            return Outcome(pause: false, retryAfter: delay(after: failures))
        default:
            return Outcome(pause: false, retryAfter: nil)
        }
    }

    /// 连续失败 n 次后的等待（1 → 30 s，2 → 2 min，≥ 3 → 10 min）。
    static func delay(after failures: Int) -> TimeInterval {
        delays[min(max(failures - 1, 0), delays.count - 1)]
    }

    /// 自动启动前：还要等多少秒（0 = 可以）；nil = 已暂停 / 连续失败用尽，只等手动连接。
    static func waitBeforeAuto(_ s: Streak, now: Date) -> TimeInterval? {
        if s.paused || s.failures >= maxFailures { return nil }
        guard s.failures > 0, let last = s.lastAttemptAt else { return 0 }
        return max(0, last.addingTimeInterval(delay(after: s.failures)).timeIntervalSince(now))
    }

    // MARK: 连续失败记录（App Group，扩展与 App 共用）

    struct Streak: Equatable, Sendable {
        /// 还没走到 connected 的连续尝试次数（进程中途被杀的那次也算）。
        var failures = 0
        var lastAttemptAt: Date?
        /// 因失败暂停了按需（App 据此关掉系统的 isOnDemandEnabled）。
        var paused = false
    }

    static let failuresKey = "reconnect.failures"
    static let lastAttemptKey = "reconnect.lastAttemptAt"
    static let pausedKey = "reconnect.pausedByFailure"

    static func streak(in d: UserDefaults = OnDemandPause.defaults()) -> Streak {
        let t = d.double(forKey: lastAttemptKey)
        return Streak(failures: d.integer(forKey: failuresKey), lastAttemptAt: t > 0 ? Date(timeIntervalSince1970: t) : nil,
                      paused: d.bool(forKey: pausedKey))
    }

    /// zm_start 之前计一次（同步落盘：内核起不来把进程拖死时，下次拉起要看得到这次）。
    static func beginAttempt(now: Date = Date(), in d: UserDefaults = OnDemandPause.defaults()) {
        d.set(streak(in: d).failures + 1, forKey: failuresKey)
        d.set(now.timeIntervalSince1970, forKey: lastAttemptKey)
        d.synchronize()
    }

    /// 连上了，或失败不归内核（不退避）：连续失败结束。
    static func reset(in d: UserDefaults = OnDemandPause.defaults()) {
        d.removeObject(forKey: failuresKey)
        d.removeObject(forKey: lastAttemptKey)
        d.removeObject(forKey: pausedKey)
    }

    /// 失败后暂停按需：显式暂停标记（与手动断开共用，TunnelController.apply 据此保持关闭）+ 失败暂停标记。
    static func pause(in d: UserDefaults = OnDemandPause.defaults()) {
        OnDemandPause.setUserPaused(true, in: d)
        d.set(true, forKey: pausedKey)
        d.synchronize()
    }

    /// 手动连接：清零并解除失败暂停（显式暂停标记由 TunnelController 清）。
    static func manualStart(in d: UserDefaults = OnDemandPause.defaults()) { reset(in: d) }
}

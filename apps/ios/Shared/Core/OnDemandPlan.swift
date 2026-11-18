// OnDemandPlan —— “按需连接 / 受信任 Wi‑Fi 自动断开”设置 → 系统按需规则的纯值描述（REVIEW-Q2 X-P1-5）。
// TunnelController 把它翻成 NEOnDemandRule；这里不依赖 NetworkExtension，便于单测。
//
//   按需连接开：先判受信任 Wi‑Fi 断开规则（若开启），其余网络一律连接。
//   只开“受信任 Wi‑Fi 自动断开”：受信任 Wi‑Fi 上断开，其他网络维持现状（不自动连接）。
//   两者都关 / 没有受信任网络且未开按需：不启用按需。

import Foundation

struct OnDemandPlan: Equatable, Sendable {
    /// 在这些 SSID 上断开（去重、去空白、保持输入顺序）。
    var disconnectSSIDs: [String]
    /// 其余网络是否自动连接。
    var connectElsewhere: Bool

    init(onDemand: Bool, trustedNetworks: [String], disconnectOnTrusted: Bool) {
        var seen = Set<String>()
        let ssids = trustedNetworks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        disconnectSSIDs = disconnectOnTrusted ? ssids : []
        connectElsewhere = onDemand
    }

    /// 没有任何规则：关闭系统按需。
    var isEmpty: Bool { disconnectSSIDs.isEmpty && !connectElsewhere }
}

/// 用户手动断开时暂停按需（#207 E02）。不另存标记，直接从系统 VPN 配置推断：
/// 有按需规则却没启用 = 用户手动断开后暂停中（`apply` 写规则时 enabled 恒等于“有规则”，只有手动断开会把两者拆开）。
enum OnDemandPause {
    static func isPaused(hasRules: Bool, enabled: Bool) -> Bool { hasRules && !enabled }

    /// 设置变化时写回系统的 isOnDemandEnabled：暂停中只更新规则、保持关闭，避免改个受信任 Wi‑Fi 就被系统重新连上。
    static func enabledAfterApply(plan: OnDemandPlan, wasPaused: Bool) -> Bool { !plan.isEmpty && !wasPaused }

    /// 手动断开：按需开着就先关掉（否则规则末尾的 Connect 会让系统立刻重连）。返回需要写入的新值，nil = 不用改。
    static func enabledBeforeStop(current: Bool) -> Bool? { current ? false : nil }

    /// 手动连接：有规则就恢复按需（按设置恢复）。返回需要写入的新值，nil = 不用改。
    static func enabledBeforeStart(hasRules: Bool, current: Bool) -> Bool? { hasRules && !current ? true : nil }
}

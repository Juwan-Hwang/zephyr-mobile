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

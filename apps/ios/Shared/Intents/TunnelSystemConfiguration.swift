// TunnelSystemConfiguration —— 系统 VPN 配置的纯构造（便于单测）：TunnelProtocolFactory（协议）与 OnDemandRules（按需规则）。
//
// TunnelProtocolFactory：首次创建系统 VPN 配置时的 NETunnelProviderProtocol。
//
// 契约 §16.a⑥（E03）：v1 **不**开 includeAllNetworks / enforceRoutes——开了会让 §16.a① 的局域网排除失效，
// 并影响 AirDrop / CarPlay 等本地功能；v1 不承诺 Kill switch。这里显式写 false，防止以后被顺手打开。

import Foundation
import NetworkExtension

enum TunnelProtocolFactory {
    static func make(providerBundleIdentifier: String, serverAddress: String) -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = serverAddress
        proto.disconnectOnSleep = false
        proto.includeAllNetworks = false
        proto.enforceRoutes = false
        return proto
    }
}

/// 按需规则（契约 §16.a⑤ E01）：OnDemandPlan → NEOnDemandRule，顺序即系统匹配顺序。
///   - `NEOnDemandRuleDisconnect(ssidMatch: trustedWifi)`：仅当 disconnectOnTrusted 且列表非空（OnDemandPlan 已去空白去重）；
///   - 末尾 `NEOnDemandRuleConnect`：按需连接开启时，其余网络一律连接；
///   - 只开受信任 Wi‑Fi 断开、按需关闭：末尾 `NEOnDemandRuleIgnore`（其他网络维持现状，不自动连）；
///   - 都没有：空数组（调用方据此关闭系统按需）。
/// 系统在每次网络变化时自己重新评估这些规则（§16.a③ 第 2 步“重评受信任 Wi‑Fi”在 iOS 上由此完成），读 SSID 不需要定位权限。
enum OnDemandRules {
    static func make(_ plan: OnDemandPlan) -> [NEOnDemandRule] {
        var rules: [NEOnDemandRule] = []
        if !plan.disconnectSSIDs.isEmpty {
            let disconnect = NEOnDemandRuleDisconnect()
            disconnect.interfaceTypeMatch = .wiFi
            disconnect.ssidMatch = plan.disconnectSSIDs
            rules.append(disconnect)
        }
        if plan.connectElsewhere { rules.append(NEOnDemandRuleConnect()) } else if !rules.isEmpty { rules.append(NEOnDemandRuleIgnore()) }
        return rules
    }
}

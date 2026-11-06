// TunnelNetworkSettingsFactory —— TunnelConfiguration → NEPacketTunnelNetworkSettings。
// 默认路由全部进隧道（IPv4 必有、IPv6 可选），DNS 指向 mihomo 的劫持地址并匹配所有域名。

import Foundation
import NetworkExtension

enum TunnelNetworkSettingsFactory {
    static func make(_ config: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        // tunnelRemoteAddress 只是标识，流量不会真的发往这里。
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let v4 = NEIPv4Settings(addresses: [config.ipv4Address], subnetMasks: [config.ipv4SubnetMask])
        v4.includedRoutes = [NEIPv4Route.default()]
        if config.bypassLAN {
            v4.excludedRoutes = TunnelConfiguration.lanIPv4.map {
                NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask)
            }
        }
        settings.ipv4Settings = v4

        if config.ipv6 {
            let v6 = NEIPv6Settings(addresses: [config.ipv6Address],
                                    networkPrefixLengths: [NSNumber(value: config.ipv6PrefixLength)])
            v6.includedRoutes = [NEIPv6Route.default()]
            if config.bypassLAN {
                v6.excludedRoutes = TunnelConfiguration.lanIPv6.map {
                    NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix))
                }
            }
            settings.ipv6Settings = v6
        }

        let dns = NEDNSSettings(servers: config.dnsServers)
        // 空字符串 = 匹配所有域名：所有 DNS 查询都交给隧道内的 mihomo（fake-ip）。
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        settings.mtu = NSNumber(value: config.mtu)

        if let port = config.httpProxyPort {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: "127.0.0.1", port: port)
            proxy.httpEnabled = true
            proxy.httpServer = server
            proxy.httpsEnabled = true
            proxy.httpsServer = server
            proxy.excludeSimpleHostnames = true
            proxy.matchDomains = [""]
            settings.proxySettings = proxy
        }
        return settings
    }
}

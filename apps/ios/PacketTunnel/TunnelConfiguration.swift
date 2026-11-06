// TunnelConfiguration —— 一次 startTunnel 所需的全部参数（纯值，便于单测）。
// 来源：SharedState.tunnel（App 从引擎 Settings 同步）+ startTunnel(options:) 覆盖 + 固定的地址规划。

import Foundation

struct TunnelConfiguration: Equatable, Sendable {
    /// mihomo 配置文件（App Group/core/config.yaml，App 写入，扩展只读）。
    var configURL: URL
    var mode: SharedState.Mode
    var mtu: Int
    var ipv6: Bool
    var bypassLAN: Bool

    // 地址规划与 mihomo 默认一致：fake-ip-range 198.18.0.1/16，tun inet4 198.18.0.1/30，DNS 劫持到 198.18.0.2。
    var ipv4Address = "198.18.0.1"
    var ipv4SubnetMask = "255.255.255.252"
    var ipv6Address = "fdfe:dcba:9876::1"
    var ipv6PrefixLength = 126
    var dnsServers = ["198.18.0.2"]
    /// 可选：系统 HTTP 代理指向 mihomo mixed-port，遵守系统代理的 App 走代理而不经 TUN（更省 NE 内存）。
    var httpProxyPort: Int?

    /// 局域网 / 链路本地 / 组播，bypassLAN 时排除出隧道。
    static let lanIPv4: [(address: String, mask: String)] = [
        ("10.0.0.0", "255.0.0.0"),
        ("127.0.0.0", "255.0.0.0"),
        ("169.254.0.0", "255.255.0.0"),
        ("172.16.0.0", "255.240.0.0"),
        ("192.168.0.0", "255.255.0.0"),
        ("224.0.0.0", "240.0.0.0"),
    ]
    static let lanIPv6: [(address: String, prefix: Int)] = [
        ("fe80::", 10),
        ("fc00::", 7),
        ("ff00::", 8),
    ]

    static let minMTU = 1280
    static let maxMTU = 9000

    static var defaultConfigURL: URL { AppGroup.coreDirectory.appendingPathComponent("config.yaml") }

    /// 从共享状态与启动参数组装。options 可含 "configPath"(String) / "mode"(String)。
    static func load(store: SharedStore = .shared, options: [String: NSObject]? = nil) -> TunnelConfiguration {
        let prefs = store.read().tunnel
        var config = TunnelConfiguration(
            configURL: defaultConfigURL,
            mode: prefs.mode,
            mtu: min(max(prefs.mtu, minMTU), maxMTU),
            ipv6: prefs.ipv6,
            bypassLAN: prefs.bypassLAN
        )
        if let path = options?["configPath"] as? String, !path.isEmpty {
            config.configURL = URL(fileURLWithPath: path)
        }
        if let raw = options?["mode"] as? String, let mode = SharedState.Mode(rawValue: raw) {
            config.mode = mode
        }
        return config
    }

}

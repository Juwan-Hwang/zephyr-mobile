// TunnelNetworkSettingsFactory：地址 / 路由（默认路由 + 局域网排除）/ IPv6 开关 / DNS 全域匹配 / MTU / 可选系统代理；
// 以及 TunnelConfiguration.load 从 SharedState 与 startTunnel options 组装（MTU 夹取、覆盖、非法值忽略）。
// A 的 TunnelConfigurationTests 覆盖地址规划常量，这里不重复。

import NetworkExtension
import XCTest

final class TunnelNetworkSettingsFactoryTests: XCTestCase {

    private func config(mtu: Int = SharedState.TunnelPreferences.defaultMTU, ipv6: Bool = false,
                        bypassLAN: Bool = true, httpProxyPort: Int? = nil) -> TunnelConfiguration {
        var c = TunnelConfiguration(configURL: URL(fileURLWithPath: "/tmp/config.yaml"), mode: .rule,
                                    mtu: mtu, ipv6: ipv6, bypassLAN: bypassLAN)
        c.httpProxyPort = httpProxyPort
        return c
    }

    // MARK: IPv4

    func testIPv4AddressAndDefaultRoute() throws {
        let s = TunnelNetworkSettingsFactory.make(config())
        XCTAssertEqual(s.tunnelRemoteAddress, "127.0.0.1")
        let v4 = try XCTUnwrap(s.ipv4Settings)
        XCTAssertEqual(v4.addresses, ["198.18.0.1"])
        XCTAssertEqual(v4.subnetMasks, ["255.255.255.252"])
        let included = try XCTUnwrap(v4.includedRoutes)
        XCTAssertEqual(included.count, 1)
        XCTAssertEqual(included.first?.destinationAddress, NEIPv4Route.default().destinationAddress)
        XCTAssertEqual(included.first?.destinationSubnetMask, NEIPv4Route.default().destinationSubnetMask)
    }

    func testBypassLANExcludesPrivateRanges() throws {
        let v4 = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(bypassLAN: true)).ipv4Settings)
        let excluded = (v4.excludedRoutes ?? []).map { "\($0.destinationAddress)/\($0.destinationSubnetMask)" }
        XCTAssertEqual(excluded, TunnelConfiguration.lanIPv4.map { "\($0.address)/\($0.mask)" })
        XCTAssertTrue(excluded.contains("10.0.0.0/255.0.0.0"))
        XCTAssertTrue(excluded.contains("172.16.0.0/255.240.0.0"))
        XCTAssertTrue(excluded.contains("192.168.0.0/255.255.0.0"))
        XCTAssertTrue(excluded.contains("169.254.0.0/255.255.0.0"))
        XCTAssertFalse(excluded.contains { $0.hasPrefix("198.18.") }, "fake-ip 段必须走隧道")
    }

    func testNoBypassLANMeansNoExcludedRoutes() throws {
        let v4 = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(bypassLAN: false)).ipv4Settings)
        XCTAssertTrue((v4.excludedRoutes ?? []).isEmpty)
    }

    // MARK: IPv6

    /// IPv6 关闭时仍把 IPv6 默认路由收进隧道（由 mihomo 丢弃），否则字面 IPv6 地址的流量绕过隧道泄露真实 IP。
    func testIPv6DisabledStillRoutesIntoTunnelToAvoidLeak() throws {
        let v6 = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(ipv6: false)).ipv6Settings)
        XCTAssertEqual(v6.includedRoutes?.first?.destinationAddress, NEIPv6Route.default().destinationAddress)
    }

    func testIPv6EnabledWithDefaultRouteAndLANExclusions() throws {
        let v6 = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(ipv6: true, bypassLAN: true)).ipv6Settings)
        XCTAssertEqual(v6.addresses, ["fdfe:dcba:9876::1"])
        XCTAssertEqual(v6.networkPrefixLengths, [126])
        let included = try XCTUnwrap(v6.includedRoutes)
        XCTAssertEqual(included.count, 1)
        XCTAssertEqual(included.first?.destinationAddress, NEIPv6Route.default().destinationAddress)
        let excluded = (v6.excludedRoutes ?? []).map { "\($0.destinationAddress)/\($0.destinationNetworkPrefixLength)" }
        XCTAssertEqual(excluded.count, TunnelConfiguration.lanIPv6.count)
        XCTAssertTrue(excluded.contains { $0.hasSuffix("/10") }, "链路本地 fe80::/10")
        XCTAssertTrue(excluded.contains { $0.hasSuffix("/7") }, "ULA fc00::/7")
    }

    func testIPv6WithoutBypassHasNoExclusions() throws {
        let v6 = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(ipv6: true, bypassLAN: false)).ipv6Settings)
        XCTAssertTrue((v6.excludedRoutes ?? []).isEmpty)
    }

    // MARK: DNS / MTU / 代理

    func testDNSPointsToMihomoAndMatchesAllDomains() throws {
        let dns = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config()).dnsSettings)
        XCTAssertEqual(dns.servers, ["198.18.0.2"])
        XCTAssertEqual(dns.matchDomains, [""], "空字符串 = 所有域名都交给隧道内 DNS")
    }

    func testMTUIsPassedThrough() {
        XCTAssertEqual(TunnelNetworkSettingsFactory.make(config()).mtu?.intValue, SharedState.TunnelPreferences.defaultMTU)
        XCTAssertEqual(TunnelNetworkSettingsFactory.make(config(mtu: 1280)).mtu?.intValue, 1280)
        XCTAssertEqual(TunnelNetworkSettingsFactory.make(config(mtu: 9000)).mtu?.intValue, 9000)
    }

    func testNoProxySettingsByDefault() {
        XCTAssertNil(TunnelNetworkSettingsFactory.make(config()).proxySettings)
    }

    func testHTTPProxyPointsToMixedPort() throws {
        let proxy = try XCTUnwrap(TunnelNetworkSettingsFactory.make(config(httpProxyPort: 7890)).proxySettings)
        XCTAssertTrue(proxy.httpEnabled)
        XCTAssertTrue(proxy.httpsEnabled)
        XCTAssertEqual(proxy.httpServer?.address, "127.0.0.1")
        XCTAssertEqual(proxy.httpServer?.port, 7890)
        XCTAssertEqual(proxy.httpsServer?.port, 7890)
        XCTAssertTrue(proxy.excludeSimpleHostnames)
        XCTAssertEqual(proxy.matchDomains, [""])
    }

    // MARK: TunnelConfiguration.load

    private func temporaryStore() throws -> (SharedStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TunnelConfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (SharedStore(directory: dir, notify: false), dir)
    }

    func testLoadUsesDefaultsWhenStoreEmpty() throws {
        let (store, dir) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = TunnelConfiguration.load(store: store)
        XCTAssertEqual(c.mode, .rule)
        XCTAssertEqual(c.mtu, SharedState.TunnelPreferences.defaultMTU)
        XCTAssertFalse(c.ipv6)
        XCTAssertTrue(c.bypassLAN)
        XCTAssertEqual(c.configURL.lastPathComponent, "config.yaml")
        XCTAssertNil(c.httpProxyPort)
    }

    func testLoadReadsPreferencesAndClampsMTU() throws {
        let (store, dir) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.update { $0.tunnel = .init(mode: .global, mtu: 100, ipv6: true, bypassLAN: false) }
        var c = TunnelConfiguration.load(store: store)
        XCTAssertEqual(c.mode, .global)
        XCTAssertEqual(c.mtu, TunnelConfiguration.minMTU)
        XCTAssertTrue(c.ipv6)
        XCTAssertFalse(c.bypassLAN)

        try store.update { $0.tunnel.mtu = 65_535 }
        c = TunnelConfiguration.load(store: store)
        XCTAssertEqual(c.mtu, TunnelConfiguration.maxMTU)
    }

    func testLoadOptionsOverrideConfigPathAndMode() throws {
        let (store, dir) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = TunnelConfiguration.load(store: store, options: [
            "configPath": "/var/tmp/override.yaml" as NSString,
            "mode": "direct" as NSString,
        ])
        XCTAssertEqual(c.configURL.path, "/var/tmp/override.yaml")
        XCTAssertEqual(c.mode, .direct)
    }

    func testLoadIgnoresInvalidOptions() throws {
        let (store, dir) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.update { $0.tunnel.mode = .global }
        let c = TunnelConfiguration.load(store: store, options: [
            "configPath": "" as NSString,
            "mode": "turbo" as NSString,
            "mtu": NSNumber(value: 1),
        ])
        XCTAssertEqual(c.mode, .global, "未知模式忽略，保留共享偏好")
        XCTAssertEqual(c.configURL, TunnelConfiguration.defaultConfigURL, "空路径忽略")
        XCTAssertEqual(c.mtu, SharedState.TunnelPreferences.defaultMTU, "options 不覆盖 MTU")
    }

    func testFactoryOutputForLoadedConfigIsConsistent() throws {
        let (store, dir) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.update { $0.tunnel = .init(mode: .rule, mtu: 1500, ipv6: true, bypassLAN: true) }
        let s = TunnelNetworkSettingsFactory.make(TunnelConfiguration.load(store: store))
        XCTAssertEqual(s.mtu?.intValue, 1500)
        XCTAssertNotNil(s.ipv6Settings)
        XCTAssertEqual(s.ipv4Settings?.excludedRoutes?.count, TunnelConfiguration.lanIPv4.count)
    }
}

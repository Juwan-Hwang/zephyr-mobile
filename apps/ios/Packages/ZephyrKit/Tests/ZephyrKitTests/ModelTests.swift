import XCTest
@testable import ZephyrKit

final class ModelTests: XCTestCase {

    func json<T: Encodable>(_ v: T) throws -> [String: Any] {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        return try JSONSerialization.jsonObject(with: enc.encode(v)) as! [String: Any]
    }

    func testSnakeCaseKeys() throws {
        let n = NodeSummary(id: 100_000_003, name: "东京 NTT BGP 01 ×2", region: "JP", city: "东京", carrier: "NTT", tag: "BGP",
                            protocol: "VLESS", multiplier: 2, latencyMs: 61)
        let j = try json(n)
        XCTAssertEqual(j["latency_ms"] as? Int, 61)
        XCTAssertEqual(j["protocol"] as? String, "VLESS")
        XCTAssertEqual(n.protocol, "VLESS")

        let s = ConnectionState(status: .connected, mode: .global, since: 1, globalNodeId: 7)
        XCTAssertEqual(try json(s)["global_node_id"] as? Int, 7)
        XCTAssertEqual(try json(TrafficSample(at: 1, upBps: 2, downBps: 3))["down_bps"] as? Int, 3)
        XCTAssertEqual(try json(RegionSection(region: "JP", name: "日本", count: 1, rowOffset: 5))["row_offset"] as? Int, 5)
        XCTAssertEqual(try json(GroupTypeBox(t: .urlTest))["t"] as? String, "url_test")
        XCTAssertEqual(try json(ZephyrError(code: .vpnPermissionDenied, message: "x"))["code"] as? String, "vpn_permission_denied")
        XCTAssertEqual(SceneSource.subscriptionGroup.rawValue, "subscription_group")
        XCTAssertEqual(CommandKind.openNodeQuery.rawValue, "open_node_query")
        XCTAssertEqual(ErrorCode.allCases.count, 14)
        XCTAssertEqual(ErrorCode.subscriptionNotFound.rawValue, "subscription_not_found")
    }

    struct GroupTypeBox: Codable { var t: GroupType }

    func testRoundTrip() throws {
        let sub = Subscription(id: "nebula", name: "Nebula Cloud", nodeCount: 8204, remainingBytes: 86_400_000_000, autoUpdateHours: 12,
                               lastDiff: SubscriptionDiff(addedNodes: 1204, removedNodes: 318, ruleChanges: 0, overridesKept: true, scenesRetested: true))
        let back = try JSONDecoder().decode(Subscription.self, from: JSONEncoder().encode(sub))
        XCTAssertEqual(back, sub)
        let st = Settings(onDemand: true, trustedWifi: ["家"], disconnectOnTrusted: true, localProxyPort: 7890, localProxyAuth: false,
                          testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12, updateOnWifiOnly: true, showChangesBeforeUpdate: true,
                          dns: DnsSettings(), tun: TunSettings(), accent: .blue, appearance: .system, shareAnonymousPattern: true)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(st)), st)
        XCTAssertNotNil(try json(st)["show_changes_before_update"])
    }

    /// #207 E09/U8：默认值与契约 §13 一致。
    func testTunnelDefaultsMatchContract() {
        XCTAssertEqual(TunSettings().stack, .gvisor)
        XCTAssertEqual(TunSettings().mtu, 9000)
        XCTAssertEqual(DnsSettings().nameservers, ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"])
        XCTAssertEqual(DnsSettings().fallback, ["https://1.1.1.1/dns-query"])
        XCTAssertTrue(DnsSettings().fakeIp)
        XCTAssertFalse(DnsSettings().ipv6)
    }

    private func legacySettingsJSON(stack: String, nameservers: [String], fallback: [String]) throws -> Data {
        let st = Settings(onDemand: false, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890, localProxyAuth: true,
                          testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12, updateOnWifiOnly: true, showChangesBeforeUpdate: true,
                          dns: DnsSettings(), tun: TunSettings(), accent: .blue, appearance: .system, shareAnonymousPattern: false)
        var obj = try json(st)
        obj["dns"] = ["fake_ip": true, "nameservers": nameservers, "fallback": fallback, "ipv6": false]
        obj["tun"] = ["stack": stack, "mtu": 9000, "ipv6": false, "strict_route": true]
        return try JSONSerialization.data(withJSONObject: obj)
    }

    /// 旧版本落盘的出厂值迁移到契约默认值。
    func testLegacyTunnelDefaultsMigrate() throws {
        let data = try legacySettingsJSON(stack: "system",
                                          nameservers: ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"],
                                          fallback: ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"])
        let s = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s.tun.stack, .gvisor)
        XCTAssertEqual(s.dns.nameservers, DnsSettings.defaultNameservers)
        XCTAssertEqual(s.dns.fallback, DnsSettings.defaultFallback)
    }

    /// DNS 不是旧出厂值（用户 / 导入改过）时一律保留，栈也不动。
    func testCustomTunnelSettingsKept() throws {
        let data = try legacySettingsJSON(stack: "system", nameservers: ["https://example.com/dns-query"],
                                          fallback: ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"])
        let s = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s.tun.stack, .system)
        XCTAssertEqual(s.dns.nameservers, ["https://example.com/dns-query"])
        XCTAssertEqual(s.dns.fallback.count, 2)
    }

    func testLocateRow() {
        let secs = [RegionSection(region: "US", name: "美国", count: 3, rowOffset: 0),
                    RegionSection(region: "JP", name: "日本", count: 2, rowOffset: 4)]
        XCTAssertEqual(secs.locate(row: 0), .header(section: 0))
        XCTAssertEqual(secs.locate(row: 1), .node(section: 0, indexInSection: 0, ordinal: 0))
        XCTAssertEqual(secs.locate(row: 3), .node(section: 0, indexInSection: 2, ordinal: 2))
        XCTAssertEqual(secs.locate(row: 4), .header(section: 1))
        XCTAssertEqual(secs.locate(row: 6), .node(section: 1, indexInSection: 1, ordinal: 4))
        XCTAssertNil(secs.locate(row: 7))
        XCTAssertEqual(LogLevel.warning > LogLevel.info, true)
    }
}

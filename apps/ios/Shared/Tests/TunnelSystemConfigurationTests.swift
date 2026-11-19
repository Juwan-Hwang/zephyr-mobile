// TunnelProtocolFactory（§16.a⑥ 不开 includeAllNetworks / enforceRoutes）与 OnDemandRules（§16.a⑤ 规则形状与顺序）。

import NetworkExtension
import XCTest

final class TunnelSystemConfigurationTests: XCTestCase {

    // MARK: §16.a⑥

    func testProtocolDoesNotEnableIncludeAllNetworksOrEnforceRoutes() {
        let p = TunnelProtocolFactory.make(providerBundleIdentifier: "com.juwanh.zephyr.PacketTunnel", serverAddress: "Zephyr")
        XCTAssertEqual(p.providerBundleIdentifier, "com.juwanh.zephyr.PacketTunnel")
        XCTAssertEqual(p.serverAddress, "Zephyr")
        XCTAssertFalse(p.includeAllNetworks, "会让局域网排除失效（§16.a⑥）")
        XCTAssertFalse(p.enforceRoutes)
        XCTAssertFalse(p.disconnectOnSleep)
    }

    // MARK: §16.a⑤

    private func rules(onDemand: Bool, trusted: [String], disconnect: Bool) -> [NEOnDemandRule] {
        OnDemandRules.make(OnDemandPlan(onDemand: onDemand, trustedNetworks: trusted, disconnectOnTrusted: disconnect))
    }

    func testTrustedDisconnectThenTrailingConnect() throws {
        let r = rules(onDemand: true, trusted: ["Home", " Office "], disconnect: true)
        XCTAssertEqual(r.count, 2)
        let d = try XCTUnwrap(r.first as? NEOnDemandRuleDisconnect)
        XCTAssertEqual(d.ssidMatch, ["Home", "Office"])
        XCTAssertEqual(d.interfaceTypeMatch, .wiFi)
        XCTAssertTrue(r.last is NEOnDemandRuleConnect, "末尾 Connect")
    }

    func testNoDisconnectRuleWhenSwitchOff() {
        let r = rules(onDemand: true, trusted: ["Home"], disconnect: false)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.first is NEOnDemandRuleConnect)
    }

    func testNoDisconnectRuleWhenListEmpty() {
        let r = rules(onDemand: true, trusted: [" ", ""], disconnect: true)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.first is NEOnDemandRuleConnect)
    }

    func testTrustedOnlyWithoutOnDemandEndsWithIgnore() {
        let r = rules(onDemand: false, trusted: ["Home"], disconnect: true)
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(r.first is NEOnDemandRuleDisconnect)
        XCTAssertTrue(r.last is NEOnDemandRuleIgnore, "按需关闭时其他网络不自动连")
    }

    func testAllOffHasNoRules() {
        XCTAssertTrue(rules(onDemand: false, trusted: [], disconnect: true).isEmpty)
        XCTAssertTrue(rules(onDemand: false, trusted: ["Home"], disconnect: false).isEmpty)
    }
}

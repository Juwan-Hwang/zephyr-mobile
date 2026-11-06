// [A] 补齐 project.yml 引用的 Shared/Tests 目录，让 CI 的 xcodegen 能生成工程。B 可继续扩充。
import XCTest

final class TunnelConfigurationTests: XCTestCase {
    func testAddressPlanMatchesMihomoDefaults() {
        let c = TunnelConfiguration(configURL: URL(fileURLWithPath: "/tmp/config.yaml"), mode: TunnelConfiguration.load().mode, mtu: 9000, ipv6: false, bypassLAN: true)
        XCTAssertEqual(c.ipv4Address, "198.18.0.1")
        XCTAssertEqual(c.ipv4SubnetMask, "255.255.255.252")
        XCTAssertEqual(c.dnsServers, ["198.18.0.2"])
        XCTAssertEqual(c.ipv6PrefixLength, 126)
    }

    func testMTUBoundsAndLANRanges() {
        XCTAssertEqual(TunnelConfiguration.minMTU, 1280)
        XCTAssertEqual(TunnelConfiguration.maxMTU, 9000)
        XCTAssertTrue(TunnelConfiguration.lanIPv4.contains { $0.address == "192.168.0.0" && $0.mask == "255.255.0.0" })
        XCTAssertTrue(TunnelConfiguration.lanIPv6.contains { $0.address == "fe80::" && $0.prefix == 10 })
    }

    func testLoadClampsMTU() {
        let c = TunnelConfiguration.load()
        XCTAssertGreaterThanOrEqual(c.mtu, TunnelConfiguration.minMTU)
        XCTAssertLessThanOrEqual(c.mtu, TunnelConfiguration.maxMTU)
    }
}

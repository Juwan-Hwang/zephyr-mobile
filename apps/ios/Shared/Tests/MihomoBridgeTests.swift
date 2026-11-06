// 扩展侧配置处理：fd 哨兵注入与模式切换（纯函数）。
import XCTest

final class MihomoBridgeTests: XCTestCase {
    let yaml = "mode: rule\nmixed-port: 0\ntun:\n  enable: true\n  file-descriptor: -1\n  mtu: 9000\n"

    func testInjectsFD() {
        let out = MihomoBridge.injectingTunFD(yaml, fd: 7)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("  file-descriptor: 7\n"))
        XCTAssertFalse(out!.contains("file-descriptor: -1"))
    }

    func testRejectsMissingSentinelOrBadFD() {
        XCTAssertNil(MihomoBridge.injectingTunFD("tun:\n  enable: false\n", fd: 7))
        XCTAssertNil(MihomoBridge.injectingTunFD(yaml, fd: -1))
    }

    func testSettingMode() {
        XCTAssertEqual(MihomoBridge.mode(in: MihomoBridge.settingMode(yaml, "global")), "global")
        XCTAssertEqual(MihomoBridge.settingMode(yaml, "bogus"), yaml)
        XCTAssertEqual(MihomoBridge.mode(in: MihomoBridge.settingMode("tun: {}\n", "direct")), "direct")
    }

    func testStubRefusesToRun() {
        XCTAssertFalse(MihomoBridge.isLinked, "单测编译不带 MIHOMO_LINKED")
    }
}

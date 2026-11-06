// MihomoBridge：扩展侧配置处理（fd 哨兵注入、mode 行）为纯函数，任何构建都测；
// 生命周期用例只在桩实现（未定义 MIHOMO_LINKED，ZephyrTests 的默认）下跑，链接真核心时 start 需要真实 tun fd。
// 每个用例新建实例，不用 .shared，避免用例之间共享 running 状态。

import XCTest

final class MihomoBridgeTests: XCTestCase {
    let yaml = "mode: rule\nmixed-port: 0\ntun:\n  enable: true\n  file-descriptor: -1\n  mtu: 9000\n"
    let home = "/tmp/zm-home"

    // MARK: 纯函数

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

    // MARK: 桩生命周期

    private func stubOnly() throws {
        try XCTSkipIf(MihomoBridge.isLinked, "已链接真实 mihomo：桩行为用例不适用")
    }

    func testStubIsNotLinked() throws {
        try stubOnly()
        XCTAssertFalse(MihomoBridge.isLinked)
    }

    func testInitialState() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        XCTAssertFalse(bridge.isRunning)
        XCTAssertEqual(bridge.currentMode, "rule")
        XCTAssertEqual(bridge.traffic(), .zero)
    }

    func testStartRejectsInvalidArguments() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        XCTAssertThrowsError(try bridge.start(homeDir: "", config: yaml, controllerSocket: "")) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .invalidArgument)
        }
        XCTAssertThrowsError(try bridge.start(homeDir: home, config: "", controllerSocket: "")) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .invalidArgument)
        }
        XCTAssertFalse(bridge.isRunning)
    }

    func testStartStopLifecycle() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        try bridge.start(homeDir: home, config: yaml, controllerSocket: "")
        XCTAssertTrue(bridge.isRunning)
        XCTAssertThrowsError(try bridge.start(homeDir: home, config: yaml, controllerSocket: "")) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .alreadyRunning)
        }
        bridge.stop()
        XCTAssertFalse(bridge.isRunning)
        bridge.stop()   // 幂等
        XCTAssertFalse(bridge.isRunning)
        try bridge.start(homeDir: home, config: yaml, controllerSocket: "")   // NE 重连
        XCTAssertTrue(bridge.isRunning)
        bridge.stop()
    }

    func testReloadRequiresRunning() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        XCTAssertThrowsError(try bridge.reload(config: yaml)) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .notRunning)
        }
        try bridge.start(homeDir: home, config: yaml, controllerSocket: "")
        XCTAssertNoThrow(try bridge.reload(config: yaml))
        bridge.stop()
    }

    func testSetModeIsRecordedRegardlessOfRunning() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        try bridge.setMode("global")
        XCTAssertEqual(bridge.currentMode, "global")
        try bridge.start(homeDir: home, config: yaml, controllerSocket: "")
        try bridge.setMode("direct")
        XCTAssertEqual(bridge.currentMode, "direct")
        bridge.stop()
        XCTAssertEqual(bridge.currentMode, "direct", "停止不重置模式")
    }

    func testMemoryCallsAreSafeInStub() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        bridge.setMemoryLimit(bytes: 40 * 1024 * 1024)
        bridge.freeOSMemory()
        XCTAssertEqual(bridge.coreMemory(), 0)
        XCTAssertFalse(bridge.isRunning)
    }

    func testConcurrentAccessIsSafe() throws {
        try stubOnly()
        let bridge = MihomoBridge()
        try bridge.start(homeDir: home, config: yaml, controllerSocket: "")
        let modes = ["rule", "global", "direct"]
        DispatchQueue.concurrentPerform(iterations: 300) { i in
            try? bridge.setMode(modes[i % modes.count])
            _ = bridge.traffic()
            _ = bridge.isRunning
            _ = bridge.currentMode
        }
        XCTAssertTrue(modes.contains(bridge.currentMode))
        bridge.stop()
    }
}

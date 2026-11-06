// MihomoBridge 桩实现（未定义 MIHOMO_LINKED）：参数校验、生命周期状态机、流量恒 0、模式记录。
// 链接真核心后（MIHOMO_LINKED）这些用例不适用：start 需要真实 tun fd，整组跳过。
// 每个用例新建实例，不用 .shared，避免用例之间共享 running 状态。

import XCTest

final class MihomoBridgeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipIf(MihomoBridge.isLinked, "已链接真实 libmihomo：桩行为用例不适用")
    }

    func testStubIsNotLinked() {
        XCTAssertFalse(MihomoBridge.isLinked)
    }

    func testInitialState() {
        let bridge = MihomoBridge()
        XCTAssertFalse(bridge.isRunning)
        XCTAssertEqual(bridge.currentMode, "rule")
        XCTAssertEqual(bridge.traffic(), .zero)
    }

    func testStartRejectsInvalidArguments() {
        let bridge = MihomoBridge()
        XCTAssertThrowsError(try bridge.start(configPath: "", tunFD: 3)) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .invalidArgument)
        }
        XCTAssertThrowsError(try bridge.start(configPath: "/tmp/config.yaml", tunFD: -1)) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .invalidArgument)
        }
        XCTAssertFalse(bridge.isRunning)
    }

    func testStartStopLifecycle() throws {
        let bridge = MihomoBridge()
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)
        XCTAssertTrue(bridge.isRunning)
        XCTAssertThrowsError(try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .alreadyRunning)
        }
        bridge.stop()
        XCTAssertFalse(bridge.isRunning)
        bridge.stop()   // 幂等
        XCTAssertFalse(bridge.isRunning)
        // 停止后可再次启动（NE 重连）。
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 4)
        XCTAssertTrue(bridge.isRunning)
        bridge.stop()
    }

    func testReloadRequiresRunning() throws {
        let bridge = MihomoBridge()
        XCTAssertThrowsError(try bridge.reload(configPath: "/tmp/config.yaml")) {
            XCTAssertEqual($0 as? MihomoBridge.BridgeError, .notRunning)
        }
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)
        XCTAssertNoThrow(try bridge.reload(configPath: "/tmp/config.yaml"))
        bridge.stop()
    }

    func testTrafficIsZeroInStub() throws {
        let bridge = MihomoBridge()
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)
        XCTAssertEqual(bridge.traffic(), .zero)
        bridge.stop()
    }

    func testSetModeIsRecordedRegardlessOfRunning() throws {
        let bridge = MihomoBridge()
        bridge.setMode("global")
        XCTAssertEqual(bridge.currentMode, "global")
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)
        bridge.setMode("direct")
        XCTAssertEqual(bridge.currentMode, "direct")
        bridge.stop()
        XCTAssertEqual(bridge.currentMode, "direct", "停止不重置模式，下次启动沿用")
    }

    func testMemoryCallsAreSafeInStub() {
        let bridge = MihomoBridge()
        bridge.setMemoryLimit(bytes: 40 * 1024 * 1024)
        bridge.freeOSMemory()
        XCTAssertFalse(bridge.isRunning)
    }

    func testConcurrentAccessIsSafe() throws {
        let bridge = MihomoBridge()
        try bridge.start(configPath: "/tmp/config.yaml", tunFD: 3)
        let modes = ["rule", "global", "direct"]
        DispatchQueue.concurrentPerform(iterations: 300) { i in
            bridge.setMode(modes[i % modes.count])
            _ = bridge.traffic()
            _ = bridge.isRunning
            _ = bridge.currentMode
        }
        XCTAssertTrue(modes.contains(bridge.currentMode))
        bridge.stop()
    }
}

// “仅在 Wi‑Fi 下测速”：滚动自动测速在计费网络下停用，手动测速不受影响（REVIEW-Q2 X-P1-5）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class AutoTestGateTests: XCTestCase {
    func testGateTruthTable() {
        XCTAssertTrue(NodesModel.autoTestAllowed(wifiOnly: false, metered: false))
        XCTAssertTrue(NodesModel.autoTestAllowed(wifiOnly: false, metered: true))
        XCTAssertTrue(NodesModel.autoTestAllowed(wifiOnly: true, metered: false))
        XCTAssertFalse(NodesModel.autoTestAllowed(wifiOnly: true, metered: true))
    }

    func testAutomaticTestSkippedWhenDisallowed() {
        let store = NodeRowStore(engine: MockEngine(seed: 0, clock: .frozen941))
        let n = NodeSummary(id: 42, name: "东京 01", region: "JP", protocol: "VLESS")
        store.autoTestAllowed = false
        XCTAssertEqual(store.testVisible([n], automatic: true), [])
        XCTAssertEqual(store.testVisible([n]), [42], "手动测速不受“仅 Wi‑Fi”限制")
    }

    func testAutomaticTestRunsWhenAllowed() {
        let store = NodeRowStore(engine: MockEngine(seed: 0, clock: .frozen941))
        let n = NodeSummary(id: 7, name: "新加坡 02", region: "SG", protocol: "Hy2")
        XCTAssertEqual(store.testVisible([n], automatic: true), [7])
    }
}

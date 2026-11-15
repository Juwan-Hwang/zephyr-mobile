// 规则页模型：120 ms 去抖只落最后一次输入、清空输入取消挂起的测试、命中链与命中行（REVIEW-Q1 L-P2-13）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class RulesModelTests: XCTestCase {
    private func makeModel(query: String? = nil) -> RulesModel {
        RulesModel(engine: MockEngine(seed: 0, clock: .frozen941), query: query)
    }

    private var debounceWindow: UInt64 { RulesModel.debounceNanos * 3 }

    func testStartLoadsStatsAndTestsDefaultInput() async throws {
        let m = makeModel()
        await m.start()
        try await waitUntil { m.trace != nil }
        XCTAssertNotNil(m.stats)
        XCTAssertEqual(m.trace?.input, RulesModel.defaultInput)
        XCTAssertFalse(m.invalid)
        XCTAssertNotNil(m.subtitle)
        XCTAssertNotNil(m.tookText)
    }

    func testDebouncedTypingOnlyLandsLatestInput() async throws {
        let m = makeModel(query: "")
        for partial in ["g", "gi", "git", "github.com"] {
            m.input = partial
            m.runTest(debounced: true)
        }
        XCTAssertNil(m.trace, "去抖期间不应有结果")
        try await waitUntil { m.trace != nil }
        XCTAssertEqual(m.trace?.input, "github.com")
        try await Task.sleep(nanoseconds: debounceWindow)
        XCTAssertEqual(m.trace?.input, "github.com", "被取消的早先输入不得覆盖最后结果")
    }

    func testClearingInputCancelsPendingTest() async throws {
        let m = makeModel(query: "")
        m.input = "github.com"
        m.runTest(debounced: true)
        m.input = "   "
        m.runTest(debounced: true)
        XCTAssertNil(m.trace)
        XCTAssertFalse(m.invalid)
        try await Task.sleep(nanoseconds: debounceWindow)
        XCTAssertNil(m.trace, "清空后挂起的测试不应落地")
    }

    func testDirectHitShowsDirectExitOnFirstLayer() async throws {
        let m = makeModel(query: "github.com")
        await m.start()
        try await waitUntil { m.trace?.input == "github.com" }
        XCTAssertEqual(m.hitRow, 0)
        XCTAssertEqual(m.steps.map(\.id), [0, 1, 2])
        XCTAssertEqual(m.steps.first?.value, .mono("github.com"))
        XCTAssertEqual(m.steps.last?.value, .text(ZL.tr("直连")))
    }

    func testRejectHitShowsBlocked() async throws {
        let m = makeModel(query: "ads.doubleclick.net")
        await m.start()
        try await waitUntil { m.trace?.input == "ads.doubleclick.net" }
        XCTAssertEqual(m.trace?.policy, "REJECT")
        XCTAssertEqual(m.steps.last?.value, .text(ZL.tr("已拦截")))
    }

    func testSceneHitShowsRegion() async throws {
        let m = makeModel(query: "chat.openai.com")
        await m.start()
        try await waitUntil { m.trace?.input == "chat.openai.com" }
        XCTAssertGreaterThanOrEqual(m.steps.count, 3)
        guard case .region = m.steps[2].value else { return XCTFail("场景命中应显示出口地区，实际 \(m.steps[2].value)") }
    }

    func testUnmatchedFallsToRemainderRow() async throws {
        let m = makeModel(query: "example.org")
        await m.start()
        try await waitUntil { m.trace?.input == "example.org" }
        XCTAssertNil(m.trace?.layerIndex)
        XCTAssertEqual(m.hitRow, m.stats?.layers.count, "未命中落到最后一行“其余流量”")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

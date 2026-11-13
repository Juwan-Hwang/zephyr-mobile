// 实时活动决策 + 场景“显著变化”判定（REVIEW-Q2 X-P1-8：补 LiveActivity / SharedStatePublisher 的测试）。

import XCTest

final class LiveActivityPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private typealias Content = ZephyrActivityAttributes.ContentState

    private func content(_ status: SharedState.Status = .connected, mode: SharedState.Mode = .rule,
                         down: Int64 = 1_000_000, scenes: [SharedState.SceneSummary] = []) -> Content {
        Content(status: status, mode: mode, downBps: down, upBps: 10_000, scenes: scenes, connectedSince: t0)
    }

    private func action(_ status: SharedState.Status, significant: Bool = false, active: Bool = true,
                        new: Content? = nil, last: Content? = nil, since: TimeInterval = 10) -> LiveActivityPolicy.Action {
        LiveActivityPolicy.action(status: status, significant: significant, hasActiveActivity: active,
                                  content: new ?? content(status), last: last,
                                  lastUpdate: t0, now: t0.addingTimeInterval(since))
    }

    func testConnectedWithoutActivityStarts() {
        XCTAssertEqual(action(.connected, active: false), .start)
    }

    func testDisconnectedOrFailedEnds() {
        XCTAssertEqual(action(.disconnected), .end)
        XCTAssertEqual(action(.failed, active: false), .end)
    }

    func testTransitionalStatesLeaveActivityAlone() {
        XCTAssertEqual(action(.connecting, active: false), .keep)
        XCTAssertEqual(action(.disconnecting), .keep)
    }

    func testSignificantChangeUpdatesImmediately() {
        let c = content()
        XCTAssertEqual(action(.connected, significant: true, new: c, last: c, since: 0.5), .update)
    }

    func testRateUpdatesAreThrottled() {
        let last = content(down: 1_000_000)
        XCTAssertEqual(action(.connected, new: content(down: 2_000_000), last: last, since: 4.9), .keep, "5 秒内不刷新")
        XCTAssertEqual(action(.connected, new: content(down: 2_000_000), last: last, since: 5), .update)
    }

    func testSmallRateChangeSkipped() {
        let last = content(down: 1_000_000)
        XCTAssertEqual(action(.connected, new: content(down: 1_040_000), last: last), .keep, "变动 < 5%")
        XCTAssertEqual(action(.connected, new: content(down: 1_050_000), last: last), .update)
    }

    func testRateFromZeroCountsAsChange() {
        XCTAssertEqual(action(.connected, new: content(down: 1), last: content(down: 0)), .update)
        XCTAssertEqual(action(.connected, new: content(down: 0), last: content(down: 0)), .keep)
    }

    func testModeOrScenesChangeUpdatesAfterInterval() {
        let last = content()
        XCTAssertEqual(action(.connected, new: content(mode: .global), last: last), .update)
        let s = SharedState.SceneSummary(id: "ai", name: "AI", region: "JP", nodeName: "东京 01", latencyMs: 80)
        XCTAssertEqual(action(.connected, new: content(scenes: [s]), last: last), .update)
    }

    func testFirstUpdateWithoutLastContent() {
        XCTAssertEqual(action(.connected, last: nil), .update)
    }

    func testContentKeepsAtMostThreeScenes() {
        let s = (0..<5).map { SharedState.SceneSummary(id: "\($0)", name: "S\($0)", region: "JP", nodeName: "n", latencyMs: nil) }
        XCTAssertEqual(content(scenes: s).scenes.count, Content.maxScenes)
    }

    // MARK: SharedStatePublisher 的场景显著变化（X-P1-15）

    private func scene(_ id: String = "ai", node: String = "东京 01", latency: Int?) -> SharedState.SceneSummary {
        SharedState.SceneSummary(id: id, name: id.uppercased(), region: "JP", nodeName: node, latencyMs: latency)
    }

    func testLatencyValueChangeIsNotSignificant() {
        XCTAssertEqual(SharedState.scenesShape([scene(latency: 80)]), SharedState.scenesShape([scene(latency: 120)]))
    }

    func testLatencyTierChangeIsSignificant() {
        XCTAssertNotEqual(SharedState.scenesShape([scene(latency: 80)]), SharedState.scenesShape([scene(latency: -1)]))
        XCTAssertNotEqual(SharedState.scenesShape([scene(latency: nil)]), SharedState.scenesShape([scene(latency: 80)]))
    }

    func testNodeOrSetChangeIsSignificant() {
        XCTAssertNotEqual(SharedState.scenesShape([scene(latency: 80)]), SharedState.scenesShape([scene(node: "新加坡 02", latency: 80)]))
        XCTAssertNotEqual(SharedState.scenesShape([scene(latency: 80)]), SharedState.scenesShape([scene(latency: 80), scene("video", latency: 80)]))
    }
}

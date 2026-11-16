// 订阅页派生值：用量比例（缺 used 时按 remaining 推算并夹在 0…1）、到期 / 用量警告阈值、
// 全部预览的 diff 合并、带符号计数（U+2212 减号）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class SubscriptionsDerivedTests: XCTestCase {
    private let day: Int64 = 86_400_000
    private let now: Int64 = 1_000 * 86_400_000

    private func model() -> SubscriptionsModel {
        let t = now
        return SubscriptionsModel(engine: MockEngine(seed: 0, clock: .frozen941), now: { t })
    }

    private func sub(used: Int64? = nil, total: Int64? = nil, remaining: Int64? = nil, expires: Int64? = nil) -> Subscription {
        Subscription(id: "s", name: "S", nodeCount: 1, usedBytes: used, totalBytes: total, remainingBytes: remaining,
                     expiresAt: expires, autoUpdateHours: 12)
    }

    func testUsageNeedsPositiveTotal() {
        let m = model()
        XCTAssertNil(m.usage(sub(used: 10)))
        XCTAssertNil(m.usage(sub(used: 10, total: 0)))
    }

    func testUsagePrefersUsedThenRemaining() {
        let m = model()
        XCTAssertEqual(m.usage(sub(used: 25, total: 100, remaining: 90)), 0.25)
        XCTAssertEqual(m.usage(sub(total: 100, remaining: 60)), 0.4)
        XCTAssertEqual(m.usage(sub(total: 100)), 0, "无用量信息记为 0")
    }

    func testUsageClamped() {
        let m = model()
        XCTAssertEqual(m.usage(sub(used: 150, total: 100)), 1)
        XCTAssertEqual(m.usage(sub(total: 100, remaining: 150)), 0)
    }

    func testWarningThresholds() {
        let m = model()
        XCTAssertTrue(m.isWarning(sub(expires: now + 6 * day)))
        XCTAssertFalse(m.isWarning(sub(expires: now + 8 * day)))
        XCTAssertTrue(m.isWarning(sub(expires: now - day)), "已过期也警告")
        XCTAssertTrue(m.isWarning(sub(used: 80, total: 100)), "用量 ≥ 80%")
        XCTAssertFalse(m.isWarning(sub(used: 79, total: 100)))
        XCTAssertFalse(m.isWarning(sub()))
    }

    func testMergeDiffs() {
        let a = SubscriptionDiff(addedNodes: 3, removedNodes: 1, ruleChanges: 2, overridesKept: true, scenesRetested: false)
        let b = SubscriptionDiff(addedNodes: 4, removedNodes: 5, ruleChanges: 0, overridesKept: false, scenesRetested: true)
        let m = SubscriptionsModel.merge(a, b)
        XCTAssertEqual(m.addedNodes, 7)
        XCTAssertEqual(m.removedNodes, 6)
        XCTAssertEqual(m.ruleChanges, 2)
        XCTAssertFalse(m.overridesKept, "任一未保留覆盖即为未保留")
        XCTAssertTrue(m.scenesRetested, "任一重测即为重测")
    }

    func testSignedUsesTrueMinus() {
        XCTAssertEqual(SubscriptionsModel.signed(1_204, plus: true), "+1,204")
        XCTAssertEqual(SubscriptionsModel.signed(318, plus: false), "\u{2212}318")
        XCTAssertFalse(SubscriptionsModel.signed(318, plus: false).hasPrefix("-"))
    }
}

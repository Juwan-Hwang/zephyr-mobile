import XCTest
@testable import ZephyrKit

final class AutoUpdatePlannerTests: XCTestCase {
    private let hour: Int64 = 3_600_000
    private let now: Int64 = 1_000 * 3_600_000

    private func sub(_ id: String, url: String? = "https://a.io/x", updatedHoursAgo: Int64?, every: Int32 = 12) -> Subscription {
        Subscription(id: id, name: id, url: url, nodeCount: 1,
                     updatedAt: updatedHoursAgo.map { now - $0 * hour }, autoUpdateHours: every)
    }

    func testOnlyOverdueRemoteSubscriptionsAreDue() {
        let subs = [sub("fresh", updatedHoursAgo: 3), sub("old", updatedHoursAgo: 13), sub("exact", updatedHoursAgo: 12),
                    sub("local", url: nil, updatedHoursAgo: 100), sub("never", updatedHoursAgo: nil)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now), ["old", "exact", "never"])
    }

    func testPerSubscriptionIntervalWinsAndFallsBackToSettings() {
        let subs = [sub("daily", updatedHoursAgo: 13, every: 24), sub("fast", updatedHoursAgo: 3, every: 2),
                    sub("inherit", updatedHoursAgo: 7, every: 0)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now), ["fast"], "inherit 无设置 → 12h，7h 未到")
    }

    func testRecentAttemptBacksOff() {
        let subs = [sub("old", updatedHoursAgo: 40)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now, lastAttempt: ["old": now - 60_000]), [])
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now,
                                             lastAttempt: ["old": now - AutoUpdatePlanner.minRetryMillis]), ["old"])
    }
}

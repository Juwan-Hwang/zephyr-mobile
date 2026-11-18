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

    func testPerSubscriptionIntervalWins() {
        let subs = [sub("daily", updatedHoursAgo: 13, every: 24), sub("fast", updatedHoursAgo: 3, every: 2)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now), ["fast"])
    }

    // E29：≤ 0 = 手动更新，与核心 dueSubscriptions 一致；不回落到设置或 12 h。
    func testZeroOrNegativeIntervalMeansManualOnly() {
        let subs = [sub("manual", updatedHoursAgo: 500, every: 0), sub("neg", updatedHoursAgo: 500, every: -1),
                    sub("manualNever", updatedHoursAgo: nil, every: 0), sub("auto", updatedHoursAgo: 13, every: 12)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now), ["auto"])
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: settings(autoUpdateHours: 1), now: now), ["auto"],
                       "设置里的间隔不覆盖订阅自己的“手动”")
    }

    private func settings(autoUpdateHours: Int32) -> Settings {
        Settings(onDemand: false, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890, localProxyAuth: false,
                 testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: autoUpdateHours, updateOnWifiOnly: true,
                 showChangesBeforeUpdate: false, dns: DnsSettings(), tun: TunSettings(), accent: .blue,
                 appearance: .system, shareAnonymousPattern: true)
    }

    func testRecentAttemptBacksOff() {
        let subs = [sub("old", updatedHoursAgo: 40)]
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now, lastAttempt: ["old": now - 60_000]), [])
        XCTAssertEqual(AutoUpdatePlanner.due(subs, settings: nil, now: now,
                                             lastAttempt: ["old": now - AutoUpdatePlanner.minRetryMillis]), ["old"])
    }
}

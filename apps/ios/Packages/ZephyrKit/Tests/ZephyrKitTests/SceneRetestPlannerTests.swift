import XCTest
@testable import ZephyrKit

final class SceneRetestPlannerTests: XCTestCase {
    let now: Int64 = 1_793_929_260_000
    let hour: Int64 = 3_600_000

    private func scene(_ id: String, tested: Int64?) -> ZephyrKit.Scene {
        ZephyrKit.Scene(id: id, kind: .other, name: id, available: 3,
                        selected: NodeSummary(id: 1, name: "n", region: "JP", protocol: "VLESS"),
                        source: .auto, testedAt: tested)
    }

    func testNothingDueWhenDisconnected() {
        XCTAssertEqual(SceneRetestPlanner.due([scene("ai", tested: nil)], settings: nil, connected: false, now: now), [])
    }

    func testNeverTestedAndExpiredAreDue() {
        let scenes = [scene("ai", tested: nil), scene("video", tested: now - 25 * hour), scene("other", tested: now - 2 * hour)]
        XCTAssertEqual(SceneRetestPlanner.due(scenes, settings: nil, connected: true, now: now), ["ai", "video"])
    }

    func testTtlFollowsSettings() {
        let s = Settings(onDemand: false, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890, localProxyAuth: false,
                         testOnWifiOnly: true, latencyTtlHours: 6, autoUpdateHours: 12, updateOnWifiOnly: true,
                         showChangesBeforeUpdate: false, dns: DnsSettings(), tun: TunSettings(), accent: .blue,
                         appearance: .system, shareAnonymousPattern: true)
        let scenes = [scene("ai", tested: now - 7 * hour), scene("video", tested: now - 5 * hour)]
        XCTAssertEqual(SceneRetestPlanner.due(scenes, settings: s, connected: true, now: now), ["ai"])
    }

    func testBackoffAfterRecentAttempt() {
        let scenes = [scene("ai", tested: nil), scene("video", tested: nil)]
        let due = SceneRetestPlanner.due(scenes, settings: nil, connected: true, now: now,
                                         lastAttempt: ["ai": now - 10 * 60_000, "video": now - 31 * 60_000])
        XCTAssertEqual(due, ["video"])
    }
}

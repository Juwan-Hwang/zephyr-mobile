import XCTest

final class OnDemandPlanTests: XCTestCase {
    func testAllOffIsEmpty() {
        XCTAssertTrue(OnDemandPlan(onDemand: false, trustedNetworks: ["Home"], disconnectOnTrusted: false).isEmpty)
        XCTAssertTrue(OnDemandPlan(onDemand: false, trustedNetworks: [], disconnectOnTrusted: true).isEmpty)
    }

    func testOnDemandConnectsEverywhere() {
        let p = OnDemandPlan(onDemand: true, trustedNetworks: ["Home"], disconnectOnTrusted: false)
        XCTAssertTrue(p.connectElsewhere)
        XCTAssertEqual(p.disconnectSSIDs, [])
        XCTAssertFalse(p.isEmpty)
    }

    func testTrustedDisconnectOnlyWhenEnabledAndCleaned() {
        let p = OnDemandPlan(onDemand: false, trustedNetworks: [" Home ", "Office", "Home", ""], disconnectOnTrusted: true)
        XCTAssertEqual(p.disconnectSSIDs, ["Home", "Office"])
        XCTAssertFalse(p.connectElsewhere)
        XCTAssertFalse(p.isEmpty)
    }
}

/// 手动断开暂停（#207 E02 / 契约 §16.a⑤）。
final class OnDemandPauseTests: XCTestCase {
    private var suite = ""
    private var d: UserDefaults!

    override func setUp() {
        suite = "OnDemandPauseTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        d.removePersistentDomain(forName: suite)
    }

    /// 没有规则时手动断开，之后打开按需：仍暂停，不能被系统立刻连回去。
    func testExplicitPauseHoldsWithoutRules() {
        XCTAssertTrue(OnDemandPause.isPaused(hasRules: false, enabled: false, userPaused: true))
        let plan = OnDemandPlan(onDemand: true, trustedNetworks: [], disconnectOnTrusted: true)
        let paused = OnDemandPause.isPaused(hasRules: false, enabled: false, userPaused: true)
        XCTAssertFalse(OnDemandPause.enabledAfterApply(plan: plan, wasPaused: paused))
        XCTAssertTrue(OnDemandPause.enabledAfterApply(plan: plan, wasPaused: false))
    }

    func testUserPausedFlagRoundTrip() {
        XCTAssertFalse(OnDemandPause.userPaused(in: d), "默认未暂停（首次连接前不暂停也不启用）")
        OnDemandPause.setUserPaused(true, in: d)
        XCTAssertTrue(OnDemandPause.userPaused(in: d))
        OnDemandPause.setUserPaused(false, in: d)
        XCTAssertFalse(OnDemandPause.userPaused(in: d))
        XCTAssertNil(d.object(forKey: OnDemandPause.userPausedKey))
    }
}

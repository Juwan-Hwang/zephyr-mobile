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

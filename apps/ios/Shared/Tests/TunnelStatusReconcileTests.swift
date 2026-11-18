import NetworkExtension
import XCTest

/// #207 E05 / E07 / E02 的纯值规则。
final class TunnelStatusReconcileTests: XCTestCase {
    private func state(_ status: SharedState.Status, since: Date? = nil, error: String? = nil) -> SharedState {
        var s = SharedState.empty
        s.connection = SharedState.Connection(status: status, mode: .global, since: since, errorCode: error)
        s.rate.downBps = 1_000; s.rate.upBps = 100
        return s
    }

    // MARK: E05

    func testStaleConnectedBecomesDisconnectedWhenSystemIsDown() {
        let fixed = state(.connected, since: Date()).reconciled(withSystem: .disconnected)
        XCTAssertEqual(fixed.connection.status, .disconnected)
        XCTAssertNil(fixed.connection.since)
        XCTAssertEqual(fixed.connection.mode, .global)
        XCTAssertEqual(fixed.rate.downBps, 0)
        XCTAssertEqual(fixed.rate.upBps, 0)
    }

    func testStaleConnectingAndDisconnectingAlsoReset() {
        XCTAssertEqual(state(.connecting).reconciled(withSystem: .disconnected).connection.status, .disconnected)
        XCTAssertEqual(state(.disconnecting).reconciled(withSystem: .disconnected).connection.status, .disconnected)
    }

    func testFailedIsKeptWhenSystemIsDown() {
        let s = state(.failed, error: "core_crashed")
        XCTAssertEqual(s.reconciled(withSystem: .disconnected), s)
    }

    func testConsistentStateUnchanged() {
        let s = state(.connected, since: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(s.reconciled(withSystem: .connected, since: Date()), s)
        XCTAssertEqual(state(.disconnected).reconciled(withSystem: .disconnected), state(.disconnected))
    }

    func testUnknownSystemStatusLeavesStateAlone() {
        let s = state(.connected, since: Date())
        XCTAssertEqual(s.reconciled(withSystem: nil), s)
    }

    func testSystemConnectedFillsStatusAndSince() {
        let since = Date(timeIntervalSince1970: 42)
        let fixed = state(.disconnected).reconciled(withSystem: .connected, since: since)
        XCTAssertEqual(fixed.connection.status, .connected)
        XCTAssertEqual(fixed.connection.since, since)
    }

    func testVPNStatusMapping() {
        XCTAssertEqual(SharedState.Status(vpn: .connected), .connected)
        XCTAssertEqual(SharedState.Status(vpn: .reasserting), .connecting)
        XCTAssertEqual(SharedState.Status(vpn: .connecting), .connecting)
        XCTAssertEqual(SharedState.Status(vpn: .disconnecting), .disconnecting)
        XCTAssertEqual(SharedState.Status(vpn: .disconnected), .disconnected)
        XCTAssertEqual(SharedState.Status(vpn: .invalid), .disconnected)
    }

    // MARK: E07

    private func vpnError(_ code: NEVPNError.Code) -> Error {
        NSError(domain: NEVPNErrorDomain, code: code.rawValue)
    }

    func testOnlyPermissionErrorsMapToPermissionDenied() {
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.configurationReadWriteFailed)), "vpn_permission_denied")
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.configurationDisabled)), "vpn_permission_denied")
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.configurationInvalid)), "internal")
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.configurationStale)), "internal")
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.connectionFailed)), "internal")
        XCTAssertEqual(TunnelStartFailure.code(for: vpnError(.configurationUnknown)), "internal")
        XCTAssertEqual(TunnelStartFailure.code(for: NSError(domain: NSCocoaErrorDomain, code: NEVPNError.Code.configurationDisabled.rawValue)), "internal")
    }

    // MARK: E02

    func testManualStopPausesOnDemandAndStartResumes() {
        XCTAssertEqual(OnDemandPause.enabledBeforeStop(current: true), false)
        XCTAssertNil(OnDemandPause.enabledBeforeStop(current: false))
        XCTAssertTrue(OnDemandPause.isPaused(hasRules: true, enabled: false))
        XCTAssertFalse(OnDemandPause.isPaused(hasRules: false, enabled: false))
        XCTAssertEqual(OnDemandPause.enabledBeforeStart(hasRules: true, current: false), true)
        XCTAssertNil(OnDemandPause.enabledBeforeStart(hasRules: false, current: false))
        XCTAssertNil(OnDemandPause.enabledBeforeStart(hasRules: true, current: true))
    }

    func testSettingsChangeWhilePausedKeepsOnDemandOff() {
        let plan = OnDemandPlan(onDemand: true, trustedNetworks: ["Home"], disconnectOnTrusted: true)
        XCTAssertFalse(OnDemandPause.enabledAfterApply(plan: plan, wasPaused: true))
        XCTAssertTrue(OnDemandPause.enabledAfterApply(plan: plan, wasPaused: false))
        let empty = OnDemandPlan(onDemand: false, trustedNetworks: [], disconnectOnTrusted: false)
        XCTAssertFalse(OnDemandPause.enabledAfterApply(plan: empty, wasPaused: false))
    }
}

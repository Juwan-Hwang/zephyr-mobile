// 外部深链的确认策略（REVIEW-Q1 H-P2-21）：改变连接状态的链接来自外部时先确认。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class DeepLinkConfirmationTests: XCTestCase {
    func testSourceDefaultsToExternalWithoutToken() {
        let url = URL(string: "zephyr://disconnect")!
        XCTAssertEqual(DeepLinkPolicy.source(of: url, trustedToken: nil), .external)
        XCTAssertEqual(DeepLinkPolicy.source(of: url, trustedToken: "short"), .external)
    }

    func testValidTokenIsTrusted() {
        let token = "abcdefghijklmnop1234"
        let url = DeepLink.disconnect.url(trustToken: token)
        XCTAssertEqual(DeepLinkPolicy.source(of: url, trustedToken: token), .trusted)
        XCTAssertEqual(DeepLinkPolicy.source(of: url, trustedToken: "abcdefghijklmnop9999"), .external)
    }

    func testRequiresConfirmationOnlyWhenStateWouldChange() {
        XCTAssertTrue(DeepLinkPolicy.requiresConfirmation(.disconnect, source: .external, isOn: true, mode: .rule))
        XCTAssertFalse(DeepLinkPolicy.requiresConfirmation(.disconnect, source: .external, isOn: false, mode: .rule))
        XCTAssertFalse(DeepLinkPolicy.requiresConfirmation(.connect, source: .external, isOn: true, mode: .rule))
        XCTAssertTrue(DeepLinkPolicy.requiresConfirmation(.mode("global"), source: .external, isOn: true, mode: .rule))
        XCTAssertFalse(DeepLinkPolicy.requiresConfirmation(.mode("rule"), source: .external, isOn: true, mode: .rule))
        XCTAssertFalse(DeepLinkPolicy.requiresConfirmation(.disconnect, source: .trusted, isOn: true, mode: .rule))
        XCTAssertFalse(DeepLinkPolicy.requiresConfirmation(.home, source: .external, isOn: true, mode: .rule))
    }

    @MainActor
    func testExternalDisconnectLinkWaitsForConfirmation() {
        let model = AppModel.preview(connected: true, frozen: true)
        model.connection.status = .connected
        XCTAssertTrue(model.handle(url: URL(string: "zephyr://disconnect")!))
        XCTAssertEqual(model.pendingLink?.link, .disconnect)
        XCTAssertEqual(model.pendingLink?.prompt.destructive, true)
        model.pendingLink = nil
        XCTAssertTrue(model.handle(url: URL(string: "zephyr://home")!))
        XCTAssertNil(model.pendingLink, "导航类链接不需要确认")
    }
}

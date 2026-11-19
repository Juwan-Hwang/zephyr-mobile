import XCTest
import ZephyrKit
@testable import ZephyrMock

final class LocalProxyCredentialMockTests: XCTestCase {
    func testFixedCredential() async {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let c = await e.localProxyCredential()
        XCTAssertEqual(c, "zephyr:mockmockmockmockmockmock")
        XCTAssertEqual(LocalProxyCredential.password(of: c).count, 24)
        let again = await e.localProxyCredential()
        XCTAssertEqual(again, c, "稳定")
    }

    func testResetGivesNewWellFormedValueDeterministically() async {
        let a = MockEngine(seed: 7, clock: .frozen941)
        let b = MockEngine(seed: 7, clock: .frozen941)
        let r1 = await a.resetLocalProxyCredential()
        let r2 = await b.resetLocalProxyCredential()
        XCTAssertEqual(r1, r2, "同种子同结果")
        XCTAssertNotEqual(r1, MockEngine.mockProxyCredential)
        XCTAssertTrue(LocalProxyCredential.isWellFormed(r1), r1)
        let now = await a.localProxyCredential()
        XCTAssertEqual(now, r1, "reset 后读到新值")
        let r3 = await a.resetLocalProxyCredential()
        XCTAssertNotEqual(r3, r1)
    }
}

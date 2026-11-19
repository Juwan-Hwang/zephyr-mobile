import XCTest
@testable import ZephyrKit

final class TrustedWifiTests: XCTestCase {
    func testTrimsAndAccepts() {
        XCTAssertEqual(TrustedWifi.check("  Home  ", existing: []), .ok("Home"))
    }

    func testEmpty() {
        XCTAssertEqual(TrustedWifi.check("   ", existing: []), .empty)
    }

    func testDuplicate() {
        XCTAssertEqual(TrustedWifi.check("Home ", existing: ["Home"]), .duplicate)
    }

    /// 32 字节按 UTF‑8 计：中文每字 3 字节，10 字 = 30 字节可以，11 字 = 33 字节不行。
    func testByteLimitIsUTF8() {
        XCTAssertEqual(TrustedWifi.check(String(repeating: "a", count: 32), existing: []), .ok(String(repeating: "a", count: 32)))
        XCTAssertEqual(TrustedWifi.check(String(repeating: "a", count: 33), existing: []), .tooLong)
        XCTAssertEqual(TrustedWifi.check(String(repeating: "家", count: 10), existing: []), .ok(String(repeating: "家", count: 10)))
        XCTAssertEqual(TrustedWifi.check(String(repeating: "家", count: 11), existing: []), .tooLong)
    }

    func testMaxCount() {
        let fifty = (0..<50).map { "net\($0)" }
        XCTAssertEqual(TrustedWifi.check("another", existing: Array(fifty.prefix(49))), .ok("another"))
        XCTAssertEqual(TrustedWifi.check("another", existing: fifty), .full)
    }
}

import XCTest
@testable import ZephyrKit

final class LocalProxyCredentialTests: XCTestCase {
    func testAlphabetExcludesConfusables() {
        XCTAssertEqual(LocalProxyCredential.alphabet.count, 56)
        for c in "0O1lI" { XCTAssertFalse(LocalProxyCredential.alphabet.contains(c), "\(c)") }
        XCTAssertEqual(Set(LocalProxyCredential.alphabet).count, LocalProxyCredential.alphabet.count, "无重复")
    }

    func testGenerateFormat() {
        for _ in 0..<200 {
            let c = LocalProxyCredential.generate()
            XCTAssertTrue(c.hasPrefix("zephyr:"))
            XCTAssertEqual(LocalProxyCredential.password(of: c).count, 24)
            XCTAssertTrue(LocalProxyCredential.isWellFormed(c), c)
        }
        XCTAssertNotEqual(LocalProxyCredential.generate(), LocalProxyCredential.generate())
    }

    func testWellFormedRejects() {
        XCTAssertFalse(LocalProxyCredential.isWellFormed(""))
        XCTAssertFalse(LocalProxyCredential.isWellFormed("zephyr:"))
        XCTAssertFalse(LocalProxyCredential.isWellFormed("admin:abcdefghijkmnpqrstuvwxyz"))
        XCTAssertFalse(LocalProxyCredential.isWellFormed("zephyr:abcdefghijkmnpqrstuvwxy"), "23 位")
        XCTAssertFalse(LocalProxyCredential.isWellFormed("zephyr:0bcdefghijkmnpqrstuvwxyz"), "含 0")
        XCTAssertTrue(LocalProxyCredential.isWellFormed("zephyr:abcdefghijkmnpqrstuvwxyz"))
    }

    func testURLs() {
        let c = "zephyr:abcdefghijkmnpqrstuvwxyz"
        XCTAssertEqual(LocalProxyCredential.url(.http, credential: c, port: 7890),
                       "http://zephyr:abcdefghijkmnpqrstuvwxyz@127.0.0.1:7890")
        XCTAssertEqual(LocalProxyCredential.url(.socks5, credential: c, port: 1080),
                       "socks5://zephyr:abcdefghijkmnpqrstuvwxyz@127.0.0.1:1080")
        XCTAssertEqual(LocalProxyCredential.user(of: c), "zephyr")
    }
}

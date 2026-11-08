import XCTest

final class ImportRequestTests: XCTestCase {
    func testParsesHttpsInstallConfig() {
        let url = URL(string: "clash://install-config?url=https%3A%2F%2Fsub.example.com%2Fa%3Ftoken%3D1&name=X")!
        XCTAssertEqual(ImportRequest.subscriptionURL(from: url), "https://sub.example.com/a?token=1")
        let mihomo = URL(string: "mihomo://install-config?url=https%3A%2F%2Fa.io%2Fs")!
        XCTAssertEqual(ImportRequest.subscriptionURL(from: mihomo), "https://a.io/s")
    }

    func testRejectsOtherSchemesHostsAndTargets() {
        for raw in [
            "zephyr://install-config?url=https%3A%2F%2Fa.io%2Fs",
            "clash://other?url=https%3A%2F%2Fa.io%2Fs",
            "clash://install-config",
            "clash://install-config?url=file%3A%2F%2F%2Fetc%2Fpasswd",
            "clash://install-config?url=javascript%3Aalert(1)",
            "clash://install-config?url=https%3A%2F%2F",
        ] {
            XCTAssertNil(ImportRequest.subscriptionURL(from: URL(string: raw)!), raw)
        }
    }

    func testHostAndInsecureFlag() {
        let secure = ImportRequest(payload: "https://sub.example.com/a")
        XCTAssertEqual(secure.host, "sub.example.com")
        XCTAssertFalse(secure.isInsecure)
        XCTAssertFalse(secure.message.contains("http）"))

        let plain = ImportRequest(payload: "http://10.0.0.2/a")
        XCTAssertTrue(plain.isInsecure)
        XCTAssertTrue(plain.message.contains("10.0.0.2"))
        XCTAssertGreaterThan(plain.message.count, secure.message.count)
    }
}

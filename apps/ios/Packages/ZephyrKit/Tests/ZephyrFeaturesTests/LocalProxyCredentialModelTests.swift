// 本地代理页凭据（契约 §16.g ①）：用户名 / 遮挡密码 / 复制地址 / 重新生成。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class LocalProxyCredentialModelTests: XCTestCase {
    private var copied: [String] = []

    private func make() -> LocalProxyCredentialModel {
        copied = []
        return LocalProxyCredentialModel(engine: MockEngine(seed: 0, clock: .frozen941)) { [weak self] in self?.copied.append($0) }
    }

    func testBeforeLoadNothingCopied() {
        let m = make()
        XCTAssertNil(m.password)
        XCTAssertEqual(m.displayedPassword, "—")
        XCTAssertEqual(m.username, "zephyr")
        XCTAssertFalse(m.copy(.http, port: 7890))
        XCTAssertTrue(copied.isEmpty)
        XCTAssertNil(m.displayedURL(.http, port: 7890))
    }

    func testMaskedByDefaultAndRevealOnTap() async {
        let m = make()
        await m.load()
        XCTAssertEqual(m.username, "zephyr")
        XCTAssertEqual(m.password, "mockmockmockmockmockmock")
        XCTAssertEqual(m.displayedPassword, String(repeating: "•", count: 24), "默认遮挡")
        XCTAssertFalse(m.displayedURL(.http, port: 7890)!.contains("mock"), "副标题也遮挡")
        m.isRevealed = true
        XCTAssertEqual(m.displayedPassword, "mockmockmockmockmockmock")
    }

    func testCopyHTTPAndSOCKS5() async {
        let m = make()
        await m.load()
        XCTAssertTrue(m.copy(.http, port: 7890))
        XCTAssertTrue(m.copy(.socks5, port: 7891))
        XCTAssertEqual(copied, ["http://zephyr:mockmockmockmockmockmock@127.0.0.1:7890",
                                "socks5://zephyr:mockmockmockmockmockmock@127.0.0.1:7891"])
        XCTAssertEqual(LocalProxyCredentialModel.clipboardLifetime, 60)
    }

    func testResetChangesPasswordAndRemasks() async {
        let m = make()
        await m.load()
        m.isRevealed = true
        await m.reset()
        XCTAssertNotEqual(m.password, "mockmockmockmockmockmock")
        XCTAssertTrue(LocalProxyCredential.isWellFormed(m.credential!))
        XCTAssertFalse(m.isRevealed, "重新生成后回到遮挡")
        XCTAssertFalse(m.isResetting)
        m.copy(.http, port: 7890)
        XCTAssertEqual(copied.last, "http://\(m.credential!)@127.0.0.1:7890")
    }
}

import XCTest

final class ControllerSocketTests: XCTestCase {
    func testRequestBytes() {
        let s = String(decoding: ControllerSocket.requestBytes(method: "DELETE", path: "/connections"), as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("DELETE /connections HTTP/1.1\r\n"))
        XCTAssertTrue(s.contains("Host: localhost\r\n"))
        XCTAssertTrue(s.contains("Connection: close\r\n"))
        XCTAssertTrue(s.hasSuffix("\r\n\r\n"))
    }

    func testStatusCode() {
        XCTAssertEqual(ControllerSocket.statusCode(Data("HTTP/1.1 204 No Content\r\nDate: x\r\n\r\n".utf8)), 204)
        XCTAssertEqual(ControllerSocket.statusCode(Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8)), 401)
        XCTAssertNil(ControllerSocket.statusCode(Data("garbage".utf8)))
        XCTAssertNil(ControllerSocket.statusCode(Data()))
    }

    func testMissingSocketFailsFast() {
        XCTAssertFalse(ControllerSocket.closeAllConnections(socketPath: "/tmp/zephyr-no-such-\(UUID().uuidString.prefix(8)).sock", timeout: 0.5))
    }

    func testOverlongPathRejected() {
        XCTAssertFalse(ControllerSocket.closeAllConnections(socketPath: "/" + String(repeating: "a", count: 200)))
    }
}

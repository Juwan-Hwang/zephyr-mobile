// App ⇄ PacketTunnel provider message：请求 / 响应编解码、线上格式固定（新旧版本 App 与扩展互通）、未知请求、体积上限。

import XCTest

final class TunnelMessageTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_793_921_213)

    private var allRequests: [TunnelRequest] {
        [.status, .traffic, .reloadConfig] + SharedState.Mode.allCases.map { .setMode($0) }
    }

    private func sampleResponse() -> TunnelResponse {
        TunnelResponse(result: .ok, status: .connected, mode: .rule, since: since,
                       upBps: 194_000, downBps: 2_800_000, upTotal: 12_345_678, downTotal: 1_800_000_000,
                       residentBytes: 23 * 1024 * 1024, errorCode: nil)
    }

    func testRequestRoundTrip() throws {
        for request in allRequests {
            let data = try XCTUnwrap(TunnelMessageCodec.encode(request))
            XCTAssertEqual(TunnelMessageCodec.decodeRequest(data), request)
        }
    }

    func testResponseRoundTrip() throws {
        var failed = sampleResponse()
        failed.result = .failed
        failed.status = .failed
        failed.since = nil
        failed.residentBytes = nil
        failed.errorCode = "core_crashed"
        for response in [sampleResponse(), failed] {
            let data = try XCTUnwrap(TunnelMessageCodec.encode(response))
            XCTAssertEqual(TunnelMessageCodec.decodeResponse(data), response)
        }
    }

    /// 线上格式是 App 与扩展之间的协议：两边可能来自不同版本，改了编码就会互不认识。
    func testRequestWireFormatIsStable() throws {
        func json(_ r: TunnelRequest) throws -> String {
            try XCTUnwrap(String(data: XCTUnwrap(TunnelMessageCodec.encode(r)), encoding: .utf8))
        }
        XCTAssertEqual(try json(.status), #"{"status":{}}"#)
        XCTAssertEqual(try json(.traffic), #"{"traffic":{}}"#)
        XCTAssertEqual(try json(.reloadConfig), #"{"reloadConfig":{}}"#)
        XCTAssertEqual(try json(.setMode(.global)), #"{"setMode":{"_0":"global"}}"#)

        XCTAssertEqual(TunnelMessageCodec.decodeRequest(Data(#"{"setMode":{"_0":"direct"}}"#.utf8)), .setMode(.direct))
    }

    func testResponseUsesMillisecondDates() throws {
        let data = try XCTUnwrap(TunnelMessageCodec.encode(sampleResponse()))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["since"] as? NSNumber)?.int64Value, 1_793_921_213_000)
        XCTAssertEqual(obj["result"] as? String, "ok")
        XCTAssertEqual(obj["status"] as? String, "connected")
    }

    /// 旧扩展收到新 App 的请求：解不出来 → 由 provider 回 `.unsupported`，不能崩。
    func testUnknownRequestDecodesToNil() {
        XCTAssertNil(TunnelMessageCodec.decodeRequest(Data(#"{"closeAllConnections":{}}"#.utf8)))
        XCTAssertNil(TunnelMessageCodec.decodeRequest(Data(#"{"setMode":{"_0":"turbo"}}"#.utf8)))
        XCTAssertNil(TunnelMessageCodec.decodeRequest(Data()))
        XCTAssertNil(TunnelMessageCodec.decodeRequest(Data([0xFF, 0x00])))
    }

    func testResponseMissingRequiredFieldDecodesToNil() {
        XCTAssertNil(TunnelMessageCodec.decodeResponse(Data(#"{"result":"ok"}"#.utf8)))
        XCTAssertNil(TunnelMessageCodec.decodeResponse(Data("[]".utf8)))
    }

    /// 新扩展回了旧 App 不认识的字段：多余字段应忽略。
    func testResponseIgnoresUnknownFields() throws {
        let data = try XCTUnwrap(TunnelMessageCodec.encode(sampleResponse()))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["futureField"] = ["nested": true]
        let extended = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(TunnelMessageCodec.decodeResponse(extended), sampleResponse())
    }

    func testMessagesStayUnderOneKilobyte() throws {
        var worst = sampleResponse()
        worst.upTotal = .max; worst.downTotal = .max; worst.upBps = .max; worst.downBps = .max
        worst.residentBytes = .max
        worst.errorCode = "network_unavailable"
        XCTAssertLessThan(try XCTUnwrap(TunnelMessageCodec.encode(worst)).count, 1024)
        for request in allRequests {
            XCTAssertLessThan(try XCTUnwrap(TunnelMessageCodec.encode(request)).count, 1024)
        }
    }
}

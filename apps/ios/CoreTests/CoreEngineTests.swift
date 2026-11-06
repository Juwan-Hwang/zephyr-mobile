// CoreEngine 端到端（iOS 模拟器上跑真 Rust 核心）：导入 → 建库 → 查询/分页 → 规则 → 场景 → 删除。
// 订阅正文由桩 fetcher 提供，不走网络。

import XCTest
import ZephyrKit


final class CoreEngineTests: XCTestCase {

    static let yaml = """
    proxies:
      - {name: "香港 01", server: hk1.example, port: 443, type: vless, uuid: 00000000-0000-0000-0000-000000000001}
      - {name: "香港 02", server: hk2.example, port: 443, type: vless, uuid: 00000000-0000-0000-0000-000000000002}
      - {name: "东京 03", server: jp3.example, port: 443, type: vless, uuid: 00000000-0000-0000-0000-000000000003}
      - {name: "洛杉矶 04", server: us4.example, port: 443, type: vless, uuid: 00000000-0000-0000-0000-000000000004}
    rules:
      - DOMAIN-SUFFIX,example.com,DIRECT
      - MATCH,DIRECT
    """

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("core-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func engine() -> CoreEngine {
        CoreEngine(dataDir: dir, mockData: false, fetcher: { _ in
            CoreEngine.FetchedBody(body: CoreEngineTests.yaml, userInfo: "upload=100; download=900; total=10000; expire=1800000000",
                                   fileName: "Demo.yaml")
        })
    }

    func testCoreLoadsAndStartsEmpty() async throws {
        let e = engine()
        XCTAssertTrue(e.isNative, "Rust 核心应能在模拟器加载")
        let idx = await e.nodeIndex()
        XCTAssertEqual(idx.total, 0)
        let summary = await e.subscriptionsSummary()
        XCTAssertEqual(summary.count, 0)
    }

    func testImportQueryRowsDelete() async throws {
        let e = engine()
        let sub = try await e.importSubscription(source: .url, payload: "https://sub.example.com/api?token=x")
        XCTAssertEqual(sub.name, "Demo")
        XCTAssertEqual(sub.nodeCount, 4)

        let idx = await e.nodeIndex()
        XCTAssertEqual(idx.total, 4)
        XCTAssertFalse(idx.sections.isEmpty)

        let all = try await e.queryNodes(query: "")
        XCTAssertEqual(all.total, 4)
        let page = try await e.nodeRows(token: all.token, offset: 0, limit: 500)
        XCTAssertEqual(page.rows.count, 4)
        XCTAssertEqual(Set(page.rows.map(\.name)), ["香港 01", "香港 02", "东京 03", "洛杉矶 04"])

        let hk = try await e.queryNodes(query: "香港")
        XCTAssertEqual(hk.total, 2)

        let storage = await e.storage()
        XCTAssertGreaterThan(storage.nodesBytes, 0)

        try await e.deleteSubscription(id: sub.id)
        let after = await e.nodeIndex()
        XCTAssertEqual(after.total, 0)
    }

    func testStaleTokenIsTransparentAfterRebuild() async throws {
        let e = engine()
        let sub = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let q = try await e.queryNodes(query: "")
        _ = try await e.updateSubscription(id: sub.id) // 重建库，旧 token 失效
        let page = try await e.nodeRows(token: q.token, offset: 0, limit: 2)
        XCTAssertEqual(page.rows.count, 2, "旧 token 自动换新继续翻页")
    }

    func testWritesTunnelConfigWithFDSentinel() async throws {
        let e = engine()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let url = dir.appendingPathComponent("tunnel/config.yaml")
        try await e.writeTunnelConfig(to: url, controllerSocket: "/tmp/zm.sock")
        let yaml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(yaml.contains("file-descriptor: -1"), "PacketTunnel 依赖该哨兵文本")
        XCTAssertTrue(yaml.contains("external-controller-unix: /tmp/zm.sock"))
        XCTAssertTrue(yaml.contains("hk1.example"))
    }

    func testTunnelConfigNeedsSubscription() async {
        let e = engine()
        do {
            try await e.writeTunnelConfig(to: dir.appendingPathComponent("c.yaml"), controllerSocket: "/tmp/zm.sock")
            XCTFail("无订阅应失败")
        } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .subscriptionInvalid)
        } catch { XCTFail("\(error)") }
    }

    func testRejectsNonLinkFromQR() async {
        let e = engine()
        do {
            _ = try await e.importSubscription(source: .qr, payload: "hello")
            XCTFail("应拒绝")
        } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .subscriptionInvalid)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testContentDispositionAndDefaultName() {
        XCTAssertEqual(CoreEngine.defaultName(URL(string: "https://api.flyairport.net/sub")), "Flyairport")
        XCTAssertEqual(CoreEngine.defaultName(nil), "本地配置")
    }
}

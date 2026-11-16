// 指令层 switch_node payload 解析（契约 §9；"sceneId:nodeId" 或纯节点 id），
// 以及资料库统计数字随引擎到位（LibraryModel.start）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class CommandPayloadTests: XCTestCase {
    private func split(_ s: String) -> (scene: String?, node: NodeId)? {
        CommandModel.splitPayload(s).map { (scene: $0.0, node: $0.1) }
    }

    func testPlainNodeId() {
        let r = split("123")
        XCTAssertNil(r?.scene)
        XCTAssertEqual(r?.node, 123)
    }

    func testSceneQualifiedNodeId() {
        let r = split("ai:123")
        XCTAssertEqual(r?.scene, "ai")
        XCTAssertEqual(r?.node, 123)
    }

    func testOnlyFirstColonSplits() {
        XCTAssertNil(split("ai:12:3"), "节点部分须是完整数字")
    }

    func testRejectsNonNumericOrEmpty() {
        XCTAssertNil(split(""))
        XCTAssertNil(split("tokyo-03"))
        XCTAssertNil(split("ai:tokyo"))
        XCTAssertNil(split("-1"), "NodeId 为无符号")
    }

    func testLibraryCountsArriveFromEngine() async throws {
        let m = LibraryModel(engine: MockEngine(seed: 0, clock: .frozen941))
        let feed = Task { await m.start() }
        defer { feed.cancel() }
        for _ in 0..<300 where m.nodeTotal == nil || m.ruleTotal == nil || m.subscriptionCount == nil
            || m.sceneCount == nil || m.settings == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(m.nodeTotal)
        XCTAssertNotNil(m.ruleTotal)
        XCTAssertNotNil(m.subscriptionCount)
        XCTAssertNotNil(m.sceneCount)
        XCTAssertNotNil(m.trustedWifiText)
        XCTAssertNotNil(m.localPortText)
        XCTAssertEqual(LibraryModel.compact(nil), nil)
        XCTAssertEqual(LibraryModel.compact(214), "214")
    }
}

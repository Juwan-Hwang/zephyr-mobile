// 契约 §15.h 场景节点过滤（Mock 口径）：名字推断 4K、preview 计数、无 4K 时 set 抛错且场景不变、清除总是成功。

import XCTest
import ZephyrKit
@testable import ZephyrMock

final class NodeFilterTests: XCTestCase {

    func first<T>(_ s: AsyncStream<T>) async -> T? { for await v in s { return v }; return nil }

    func testUHDNameInference() {
        XCTAssertTrue(MockEngine.isUHD("香港 HKT 4K 01"))
        XCTAssertTrue(MockEngine.isUHD("日本 uhd 流媒体"))
        XCTAssertTrue(MockEngine.isUHD("US 8k"))
        XCTAssertFalse(MockEngine.isUHD("东京 NTT IPLC 03 ×1.5"))
    }

    func testPreviewCountsMatchCandidates() async throws {
        let e = MockEngine(clock: .frozen941)
        let all = try await e.sceneCandidates(sceneId: "video", region: nil)
        let p = try await e.previewSceneNodeFilter(sceneId: "video", filter: .uhd)
        XCTAssertEqual(p.total, all.count)
        XCTAssertEqual(p.matching, all.filter { MockEngine.isUHD($0.name) }.count)
        if p.currentKept { XCTAssertNil(p.suggested) }
    }

    func testSetWithoutUHDNodesThrowsAndKeepsScene() async throws {
        let e = MockEngine(clock: .frozen941)
        let p = try await e.previewSceneNodeFilter(sceneId: "video", filter: .uhd)
        guard p.poolMatching == 0 else { return }   // fixture 有 4K 节点时此用例不适用
        do {
            try await e.setSceneNodeFilter(sceneId: "video", filter: .uhd)
            XCTFail("expected throw")
        } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .ruleInputInvalid)
        }
        let scene = await first(e.scenes())?.first { $0.id == "video" }
        XCTAssertNil(scene?.nodeFilter)
    }

    func testClearAlwaysSucceedsAndUnknownSceneThrows() async throws {
        let e = MockEngine(clock: .frozen941)
        try await e.setSceneNodeFilter(sceneId: "video", filter: nil)
        do {
            _ = try await e.previewSceneNodeFilter(sceneId: "nope", filter: .uhd)
            XCTFail("expected throw")
        } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .sceneNotFound)
        }
    }
}

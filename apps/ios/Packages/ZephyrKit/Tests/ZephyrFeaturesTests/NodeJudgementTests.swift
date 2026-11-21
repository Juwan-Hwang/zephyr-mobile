// 节点页判断句（契约 §18.a 三行表）：读 NodeIndex.reachableCount / funnelTested，取不到退回「已检测 N」。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class NodeJudgementTests: XCTestCase {
    private func text(_ i: NodeIndex) -> String { String(NodesModel.judgement(index: i).characters) }

    func testReachableAndTestedFromSameFunnel() {
        let i = NodeIndex(total: 100, sections: [], testedCount: 999, reachableCount: 7, funnelTested: 9)
        let s = text(i)
        XCTAssertTrue(s.contains("7"), s)
        XCTAssertTrue(s.contains("9"), s)
        XCTAssertFalse(s.contains("999"), s)   // 不读另外的 testedCount
    }

    func testNilReachableFallsBackToTestedCount() {
        let i = NodeIndex(total: 100, sections: [], testedCount: 42)
        XCTAssertNil(i.reachableCount)
        XCTAssertNil(i.funnelTested)
        XCTAssertTrue(text(i).contains("42"))
    }

    func testFunnelTestedIsDroppedWithoutReachable() {
        let i = NodeIndex(total: 1, sections: [], testedCount: 0, reachableCount: nil, funnelTested: 5)
        XCTAssertNil(i.funnelTested)
    }

    func testCodableKeepsOptionalFields() throws {
        let i = NodeIndex(total: 3, sections: [], testedCount: 2, reachableCount: 1, funnelTested: 2)
        let back = try JSONDecoder().decode(NodeIndex.self, from: JSONEncoder().encode(i))
        XCTAssertEqual(back, i)
        let old = try JSONDecoder().decode(NodeIndex.self, from: Data(#"{"total":3,"sections":[],"tested_count":2}"#.utf8))
        XCTAssertNil(old.reachableCount)
    }
}

// 指令建议列表的稳定 id（REVIEW-Q1 H-P2-16）。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class SuggestionKeyTests: XCTestCase {
    private let a = CommandSuggestion(kind: .switchNode, title: "日本 东京 01", payload: "12")
    private let b = CommandSuggestion(kind: .switchMode, title: "全局", payload: "global")

    func testKeyFollowsSuggestionNotPosition() {
        let k1 = CommandResults.keyed([a, b]).map(\.key)
        let k2 = CommandResults.keyed([b, a]).map(\.key)
        XCTAssertEqual(k1[0], k2[1])
        XCTAssertEqual(k1[1], k2[0])
    }

    func testDuplicatesStayUnique() {
        let keys = CommandResults.keyed([a, a, b]).map(\.key)
        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(CommandResults.keyed([a, a, b]).map(\.index), [0, 1, 2])
    }
}

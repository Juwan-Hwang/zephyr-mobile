// 指令结果分组（规范 §9.5）：固定组序、空组不出现、组内保持引擎顺序；回车执行分组后的第一行。
import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class CommandGroupTests: XCTestCase {
    private func s(_ kind: CommandKind, _ title: String) -> CommandSuggestion {
        CommandSuggestion(kind: kind, title: title, payload: title)
    }

    func testGroupsInFixedOrderSkippingEmpty() {
        let list = [s(.openPage, "设置"), s(.switchNode, "东京 03"), s(.testRule, "a.com"),
                    s(.switchNode, "大阪 01"), s(.switchMode, "全局")]
        let groups = CommandResults.groups(list)
        XCTAssertEqual(groups.map(\.group), [.command, .scene, .settings, .ruleTest])
        XCTAssertEqual(groups[1].items.map(\.title), ["东京 03", "大阪 01"])
    }

    func testFirstRowFollowsGroupOrder() {
        let list = [s(.openNodeQuery, "东京"), s(.toggleConnection, "连接")]
        XCTAssertEqual(CommandResults.firstRow(list)?.title, "连接")
        XCTAssertNil(CommandResults.firstRow([]))
    }

    // MARK: 硬件键盘移动（J-3）

    func testVisibleRowsFollowGroupOrderAndLimit() {
        let nodes = (1...7).map { s(.openNodeQuery, "节点 \($0)") }
        let list = nodes + [s(.switchMode, "全局")]
        let rows = CommandResults.visibleRows(list, expanded: [])
        XCTAssertEqual(rows.map(\.suggestion.title), ["全局"] + (1...5).map { "节点 \($0)" })
        XCTAssertEqual(CommandResults.visibleRows(list, expanded: [.node]).count, 8)
    }

    func testMoveWithoutPrimaryStartsFromDefaultFirstRow() {
        let rows = ["a", "b", "c"]
        XCTAssertEqual(CommandResults.moveHighlight(from: nil, rows: rows, by: 1, hasPrimary: false), "b")
        XCTAssertEqual(CommandResults.moveHighlight(from: "b", rows: rows, by: -1, hasPrimary: false), "a")
        XCTAssertEqual(CommandResults.moveHighlight(from: "a", rows: rows, by: -1, hasPrimary: false), "a")
        XCTAssertEqual(CommandResults.moveHighlight(from: "c", rows: rows, by: 1, hasPrimary: false), "c")
    }

    func testMoveWithPrimaryCanReturnToPreview() {
        let rows = ["a", "b"]
        XCTAssertEqual(CommandResults.moveHighlight(from: nil, rows: rows, by: 1, hasPrimary: true), "a")
        XCTAssertNil(CommandResults.moveHighlight(from: "a", rows: rows, by: -1, hasPrimary: true))
        XCTAssertNil(CommandResults.moveHighlight(from: nil, rows: rows, by: -1, hasPrimary: true))
    }

    func testMoveIgnoresStaleKeyAndEmptyRows() {
        XCTAssertEqual(CommandResults.moveHighlight(from: "gone", rows: ["a", "b"], by: 1, hasPrimary: false), "b")
        XCTAssertNil(CommandResults.moveHighlight(from: nil, rows: [], by: 1, hasPrimary: false))
    }
}

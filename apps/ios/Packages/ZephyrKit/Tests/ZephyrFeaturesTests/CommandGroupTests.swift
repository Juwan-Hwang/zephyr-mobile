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
}

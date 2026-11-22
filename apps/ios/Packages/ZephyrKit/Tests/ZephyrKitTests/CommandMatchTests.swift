// 指令栏本地行触发规则（#1 A 2026-11-22 20:43）：执行类整词或前缀 ≥ 2，导航类子串。
import XCTest
@testable import ZephyrKit

final class CommandMatchTests: XCTestCase {
    func testActionRowsNeedWholeWordOrTwoCharPrefix() {
        let toggle = CommandMatch.toggleAliases + ["连接"]
        XCTAssertTrue(CommandMatch.action("开", names: toggle))          // 整词别名
        XCTAssertTrue(CommandMatch.action("co", names: toggle))          // 前缀 ≥ 2 → connect
        XCTAssertTrue(CommandMatch.action("disc", names: toggle))
        XCTAssertFalse(CommandMatch.action("c", names: toggle))          // 单字符前缀不触发执行类
        XCTAssertFalse(CommandMatch.action("nect", names: toggle))       // 执行类不认子串
        XCTAssertTrue(CommandMatch.action("gl", names: ["全局", "global"]))
        XCTAssertFalse(CommandMatch.action("g", names: ["全局", "global"]))
        XCTAssertFalse(CommandMatch.action("", names: toggle))
    }

    func testNavigationRowsMatchSubstring() {
        let subs = ["订阅", "sub", "subscriptions"]
        XCTAssertTrue(CommandMatch.navigation("scrip", names: subs))
        XCTAssertTrue(CommandMatch.navigation("s", names: subs))
        XCTAssertFalse(CommandMatch.navigation("xyz", names: subs))
        XCTAssertTrue(CommandMatch.navigation(CommandMatch.normalize("  SUB "), names: subs))
    }
}

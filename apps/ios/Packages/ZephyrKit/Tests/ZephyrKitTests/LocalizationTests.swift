import XCTest
@testable import ZephyrKit

final class LocalizationTests: XCTestCase {
    func testUntranslatedPassesThrough() {
        XCTAssertNil(ZL.bundle)                       // 单测不查表：输出稳定的中文
        XCTAssertEqual(ZL.tr("已取消"), "已取消")
        XCTAssertEqual(ZL.f("%lld 分钟前", Int64(5)), "5 分钟前")
        XCTAssertEqual(ZL.s("%@到期", "11月9日"), "11月9日到期")
    }

    func testStringArgsSupportPositional() {
        XCTAssertEqual(ZL.s("%2$@ / %1$@", "a", "b"), "b / a")
        XCTAssertEqual(ZL.s("%@ 和 %@", "x", "y"), "x 和 y")
        XCTAssertEqual(ZL.s("无参数"), "无参数")
    }

    func testRelativeAndExpiryStillChinese() {
        let now: Int64 = 1_793_929_260_000
        XCTAssertEqual(ZFormat.relative(now - 5 * 60_000, now: now), "5 分钟前")
        XCTAssertEqual(ZFormat.relative(now + 2 * 3_600_000, now: now), "2 小时后")
        XCTAssertEqual(ZFormat.relative(now - 10_000, now: now), "刚刚")
        XCTAssertEqual(ZFormat.relative(now + 10_000, now: now), "即将")
        XCTAssertEqual(ZFormat.relative(now - 3 * 86_400_000, now: now), "3 天前")
        XCTAssertEqual(ZFormat.expiry(now + 26 * 86_400_000, now: now), "26 天后到期")
        XCTAssertEqual(ZFormat.shortWeekdayName(2), "周一")
        XCTAssertEqual(ZFormat.weekdayName(6), "星期五")
    }
}

final class LocalizationContextTests: XCTestCase {
    /// 无 bundle（单测）时带上下文的键回落到中文原文，不露出 `#列表`。
    func testContextKeyFallsBackToPlainKey() {
        XCTAssertNil(ZL.bundle)
        XCTAssertEqual(ZL.tr("规则", context: "列表"), "规则")
    }

    /// 表里的上下文键：zh-Hans 写回原文，英文为复数页面标题。
    func testRulesListTitleEntry() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let entry = (json?["strings"] as? [String: Any])?["规则#列表"] as? [String: Any]
        let locs = try XCTUnwrap(entry?["localizations"] as? [String: Any])
        func value(_ l: String) -> String? {
            ((locs[l] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        XCTAssertEqual(value("zh-Hans"), "规则")
        XCTAssertEqual(value("en"), "Rules")
        XCTAssertEqual(locs.count, 14)
    }
}

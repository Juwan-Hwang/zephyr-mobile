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

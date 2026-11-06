import XCTest
@testable import ZephyrKit

final class FormatTests: XCTestCase {
    let sh = TimeZone(identifier: "Asia/Shanghai")!
    /// 2026-11-06 09:41 +08:00
    let now: Int64 = 1_793_929_260_000

    func testBytes() {
        XCTAssertEqual(ZFormat.bytes(1_800_000_000), "1.8 GB")
        XCTAssertEqual(ZFormat.bytes(86_400_000_000), "86.4 GB")
        XCTAssertEqual(ZFormat.bytes(12_000_000_000), "12.0 GB")
        XCTAssertEqual(ZFormat.bytes(600_000_000), "600 MB")
        XCTAssertEqual(ZFormat.bytes(42_300_000), "42.3 MB")
        XCTAssertEqual(ZFormat.bytes(38_000), "38 KB")
        XCTAssertEqual(ZFormat.bytes(0), "0 B")
        XCTAssertEqual(ZFormat.bytes(-5), "0 B")
        XCTAssertEqual(ZFormat.bytes(2_500_000_000_000), "2.5 TB")
        XCTAssertEqual(ZFormat.bytesParts(1_800_000_000).value, "1.8")
        XCTAssertEqual(ZFormat.bytesParts(1_800_000_000).unit, "GB")
    }

    func testRate() {
        XCTAssertEqual(ZFormat.rate(2_800_000).value, "2.8")
        XCTAssertEqual(ZFormat.rate(2_800_000).unit, "MB/s")
        XCTAssertEqual(ZFormat.rate(195_000).value, "195")
        XCTAssertEqual(ZFormat.rate(195_000).unit, "KB/s")
        XCTAssertEqual(ZFormat.rateString(194_400), "194 KB/s")
        XCTAssertEqual(ZFormat.rateString(999_700), "1.0 MB/s")
        XCTAssertEqual(ZFormat.rateString(512), "512 B/s")
    }

    func testCount() {
        XCTAssertEqual(ZFormat.count(13_109_802), "13,109,802")
        XCTAssertEqual(ZFormat.count(103_606_731), "103,606,731")
        XCTAssertEqual(ZFormat.count(8204), "8,204")
        XCTAssertEqual(ZFormat.count(999), "999")
        XCTAssertEqual(ZFormat.count(0), "0")
        XCTAssertEqual(ZFormat.count(-1204), "-1,204")
    }

    func testDurationAndLatency() {
        XCTAssertEqual(ZFormat.duration((2 * 3600 + 14 * 60 + 7) * 1000), "2:14:07")
        XCTAssertEqual(ZFormat.duration(247_000), "0:04:07")
        XCTAssertEqual(ZFormat.duration(0), "0:00:00")
        XCTAssertEqual(ZFormat.latency(38), "38 ms")
        XCTAssertEqual(ZFormat.latency(nil), "—")
        XCTAssertEqual(ZFormat.latency(-1), "超时")
    }

    func testRelative() {
        XCTAssertEqual(ZFormat.relative(now - 2 * 3_600_000, now: now), "2 小时前")
        XCTAssertEqual(ZFormat.relative(now - 5 * 60_000, now: now), "5 分钟前")
        XCTAssertEqual(ZFormat.relative(now - 10_000, now: now), "刚刚")
        XCTAssertEqual(ZFormat.relative(now - 3 * 86_400_000, now: now), "3 天前")
        XCTAssertEqual(ZFormat.relative(now + 26 * 86_400_000 + 1000, now: now), "26 天后")
    }

    func testExpiryAndDates() {
        XCTAssertEqual(ZFormat.expiry(now + 26 * 86_400_000 + 3 * 3_600_000, now: now, timeZone: sh), "26 天后到期")
        XCTAssertEqual(ZFormat.expiry(now + 3 * 86_400_000 + 4 * 3_600_000, now: now, timeZone: sh), "11月9日到期")
        XCTAssertEqual(ZFormat.expiry(now + 3_600_000, now: now, timeZone: sh), "今天到期")
        XCTAssertEqual(ZFormat.expiry(now - 1, now: now, timeZone: sh), "已到期")
        XCTAssertEqual(ZFormat.dayTitle(now, timeZone: sh), "11月6日 · 星期五")
        XCTAssertEqual(ZFormat.clock(now, timeZone: sh), "9:41")
    }
}

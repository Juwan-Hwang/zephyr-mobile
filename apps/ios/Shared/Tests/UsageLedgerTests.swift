import XCTest

final class UsageLedgerTests: XCTestCase {
    private var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }()

    private func at(_ h: Int, _ m: Int = 0, day: Int = 8) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    func testAccumulatesDeltasAndOnlineTime() {
        var l = UsageLedger.empty(at(9), calendar: cal)
        l.record(total: 1000, at: at(9), calendar: cal)
        l.record(total: 1500, at: at(9).addingTimeInterval(5), calendar: cal)
        l.record(total: 1500, at: at(9).addingTimeInterval(3600), calendar: cal)   // 挂起很久：在线只记 10 s
        XCTAssertEqual(l.hourly[9], 1500)
        XCTAssertEqual(l.todayBytes, 1500)
        XCTAssertEqual(l.onlineMillis, 15_000)
    }

    func testCounterResetAfterRestart() {
        var l = UsageLedger.empty(at(9), calendar: cal)
        l.record(total: 5000, at: at(9), calendar: cal)
        l.tunnelStarted()
        l.record(total: 200, at: at(10), calendar: cal)
        l.record(total: 100, at: at(10, 1), calendar: cal)   // 读数变小：整份计入
        XCTAssertEqual(l.hourly[9], 5000)
        XCTAssertEqual(l.hourly[10], 300)
    }

    func testRollsOverAtMidnight() {
        var l = UsageLedger.empty(at(23), calendar: cal)
        l.record(total: 100, at: at(23), calendar: cal)
        l.record(total: 400, at: at(0, 1, day: 9), calendar: cal)
        XCTAssertEqual(l.todayBytes, 300)
        XCTAssertEqual(l.hourly[0], 300)
        XCTAssertEqual(l.today(at(1, day: 10), calendar: cal).todayBytes, 0)
    }

    func testPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        var l = UsageLedger.empty(at(9), calendar: cal)
        l.record(total: 42, at: at(9), calendar: cal)
        l.save(to: url)
        XCTAssertEqual(UsageLedger.load(from: url), l)
        try? FileManager.default.removeItem(at: url)
    }
}

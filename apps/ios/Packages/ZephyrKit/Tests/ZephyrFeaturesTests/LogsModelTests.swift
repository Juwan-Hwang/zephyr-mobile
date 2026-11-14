// 日志页模型：容量裁剪、暂停、导出格式、级别切换重新订阅。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class LogsModelTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testFormatUsesTimeBadgeAndMessage() {
        let line = LogLine(at: 1_800_000_000_123, level: .warning, message: "dns timeout")
        XCTAssertEqual(LogsModel.format(line, timeZone: utc), "08:00:00.123 W dns timeout")
        XCTAssertEqual(LogsModel.badge(.debug), "D")
        XCTAssertEqual(LogsModel.badge(.error), "E")
    }

    func testCapacityKeepsNewestLines() {
        let m = LogsModel(engine: MockEngine(seed: 0, clock: .frozen941))
        for i in 0..<(LogsModel.capacity + 20) { m.append(LogLine(at: Int64(i), level: .info, message: "\(i)")) }
        XCTAssertEqual(m.lines.count, LogsModel.capacity)
        XCTAssertEqual(m.lines.first?.message, "20")
        XCTAssertEqual(m.lines.last?.message, "\(LogsModel.capacity + 19)")
    }

    func testPauseStopsAppendingAndClearEmpties() {
        let m = LogsModel(engine: MockEngine(seed: 0, clock: .frozen941))
        m.append(LogLine(at: 1, level: .info, message: "a"))
        m.isPaused = true
        m.append(LogLine(at: 2, level: .info, message: "b"))
        XCTAssertEqual(m.lines.map(\.message), ["a"])
        m.clear()
        XCTAssertTrue(m.lines.isEmpty)
    }

    func testExportJoinsLines() {
        let m = LogsModel(engine: MockEngine(seed: 0, clock: .frozen941))
        m.append(LogLine(at: 0, level: .info, message: "a"))
        m.append(LogLine(at: 1_000, level: .error, message: "b"))
        XCTAssertEqual(m.exportText(timeZone: utc), "00:00:00.000 I a\n00:00:01.000 E b")
    }

    func testStartReceivesBacklogAndLevelFilters() async throws {
        let m = LogsModel(engine: MockEngine(seed: 0, clock: .frozen941))
        m.level = .debug
        m.start()
        try await waitUntil { !m.lines.isEmpty }
        m.level = .error
        try await waitUntil { m.lines.allSatisfy { $0.level == .error } }
        m.stop()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// SharedStore：往返、损坏 / 缺失 / schema 不兼容回退、读-改-写不覆盖其他字段、缓存失效。
// 每个用例用独立的临时目录 + notify: false，不碰真正的 App Group 文件，也不发 Darwin 通知。

import XCTest

final class SharedStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!

    /// 整毫秒的固定时间（编码用 millisecondsSince1970，亚毫秒会被截断）。
    private let now = Date(timeIntervalSince1970: 1_793_929_260)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SharedStore(directory: directory, notify: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// updatedAt 由 update 写入 Date()，比较时对齐。
    private func assertEqualIgnoringTimestamp(_ a: SharedState, _ b: SharedState, file: StaticString = #filePath, line: UInt = #line) {
        var a = a, b = b
        XCTAssertEqual(a.updatedAt.timeIntervalSince1970, b.updatedAt.timeIntervalSince1970, accuracy: 0.002, file: file, line: line)
        a.updatedAt = b.updatedAt
        XCTAssertEqual(a, b, file: file, line: line)
    }

    private func assertIsEmptyFallback(_ s: SharedState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.version, SharedState.schemaVersion, file: file, line: line)
        XCTAssertEqual(s.updatedAt, Date(timeIntervalSince1970: 0), file: file, line: line)
        XCTAssertEqual(s.connection.status, .disconnected, file: file, line: line)
        XCTAssertTrue(s.scenes.isEmpty, file: file, line: line)
        XCTAssertEqual(s.usage.hourly.count, 24, file: file, line: line)
        XCTAssertEqual(s.tunnel, SharedState.TunnelPreferences(), file: file, line: line)
    }

    // MARK: 往返

    func testMissingFileReadsEmpty() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        assertIsEmptyFallback(store.read())
    }

    func testWriteReadRoundTrip() throws {
        var state = SharedState.prototype(now: now)
        state.accent = "pink"
        state.tunnel = .init(mode: .global, mtu: 1500, ipv6: true, bypassLAN: false)
        try store.write(state)

        let read = store.read()
        XCTAssertEqual(read.version, SharedState.schemaVersion)
        assertEqualIgnoringTimestamp(read, { var s = state; s.updatedAt = read.updatedAt; return s }())
        XCTAssertEqual(read.scenes.map(\.nodeName), ["东京 03", "香港 HKT", "TW-Fixed-01"])
        XCTAssertEqual(read.connection.since, state.connection.since)
    }

    func testUpdateReturnsWhatWasWritten() throws {
        let written = try store.update { $0 = SharedState.prototype(now: now) }
        // 新建 SharedStore 绕开缓存，确保读的是磁盘内容。
        let fresh = SharedStore(directory: directory, notify: false).read()
        assertEqualIgnoringTimestamp(fresh, written)
    }

    func testUpdatePreservesFieldsOwnedByOthers() throws {
        try store.write(SharedState.prototype(now: now))
        // 隧道进程只改连接状态。
        try store.update { $0.connection.status = .disconnecting }
        let read = store.read()
        XCTAssertEqual(read.connection.status, .disconnecting)
        XCTAssertEqual(read.scenes.count, 3, "场景摘要不应被覆盖")
        XCTAssertEqual(read.usage.todayBytes, 1_800_000_000)
    }

    func testUpdateStampsVersionAndTime() throws {
        let before = Date()
        let written = try store.update { $0.version = 999; $0.updatedAt = .distantPast }
        XCTAssertEqual(written.version, SharedState.schemaVersion)
        XCTAssertGreaterThanOrEqual(written.updatedAt.timeIntervalSince1970, before.timeIntervalSince1970 - 0.001)
    }

    func testReadReflectsSubsequentWrites() throws {
        try store.write(SharedState.prototype(now: now))
        XCTAssertEqual(store.read().connection.status, .connected)
        try store.update { $0.connection.status = .failed; $0.connection.errorCode = "core_crashed" }
        let read = store.read()
        XCTAssertEqual(read.connection.status, .failed)
        XCTAssertEqual(read.connection.errorCode, "core_crashed")
    }

    func testFileIsSortedKeysJSONWithMillisecondDates() throws {
        try store.write(SharedState.prototype(now: now))
        let json = try XCTUnwrap(String(data: Data(contentsOf: store.url), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix("{\"accent\":"), "sortedKeys：accent 应排第一")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        let conn = try XCTUnwrap(obj["connection"] as? [String: Any])
        let since = try XCTUnwrap(conn["since"] as? NSNumber)
        XCTAssertEqual(since.int64Value, Int64((now.timeIntervalSince1970 - (2 * 3600 + 14 * 60 + 7)) * 1000))
    }

    // MARK: 损坏回退

    func testCorruptFileFallsBackToEmpty() throws {
        try Data("{ not json".utf8).write(to: store.url)
        assertIsEmptyFallback(store.read())
    }

    func testTruncatedFileFallsBackToEmpty() throws {
        try store.write(SharedState.prototype(now: now))
        let data = try Data(contentsOf: store.url)
        try data.prefix(data.count / 2).write(to: store.url)
        assertIsEmptyFallback(SharedStore(directory: directory, notify: false).read())
    }

    func testBinaryGarbageFallsBackToEmpty() throws {
        try Data([0x00, 0xFF, 0xFE, 0x13, 0x37]).write(to: store.url)
        assertIsEmptyFallback(store.read())
    }

    func testIncompatibleSchemaFallsBackToEmpty() throws {
        var future = SharedState.prototype(now: now)
        future.version = SharedState.schemaVersion + 1
        try SharedStore.encoder.encode(future).write(to: store.url)
        assertIsEmptyFallback(store.read())
    }

    func testUpdateOverCorruptFileStartsFromEmpty() throws {
        try Data("garbage".utf8).write(to: store.url)
        try store.update { $0.accent = "green" }
        let read = store.read()
        XCTAssertEqual(read.accent, "green")
        XCTAssertEqual(read.connection.status, .disconnected)
        XCTAssertTrue(read.scenes.isEmpty)
    }

    func testResetRemovesFile() throws {
        try store.write(SharedState.prototype(now: now))
        store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        assertIsEmptyFallback(store.read())
    }

    // MARK: SharedState 纯逻辑

    func testRatePushKeepsLastCapacitySamples() {
        var rate = SharedState.Rate(downBps: 0, upBps: 0, at: nil, recentDown: [])
        for i in 0..<(SharedState.Rate.capacity + 7) {
            rate.push(down: Int64(i), up: Int64(i * 2), at: now)
        }
        XCTAssertEqual(rate.recentDown.count, SharedState.Rate.capacity)
        XCTAssertEqual(rate.recentDown.first, 7)
        XCTAssertEqual(rate.recentDown.last, Int64(SharedState.Rate.capacity + 6))
        XCTAssertEqual(rate.upBps, Int64((SharedState.Rate.capacity + 6) * 2))
        XCTAssertEqual(rate.at, now)
    }

    func testUsageResetsOnNewDay() {
        let state = SharedState.prototype(now: now)
        XCTAssertEqual(state.usage(on: now).todayBytes, 1_800_000_000)
        let tomorrow = now.addingTimeInterval(24 * 3600)
        let usage = state.usage(on: tomorrow)
        XCTAssertEqual(usage.todayBytes, 0)
        XCTAssertEqual(usage.hourly, Array(repeating: 0, count: 24))
        XCTAssertNil(usage.fastestLatencyMs)
    }

    func testStatusIsOn() {
        XCTAssertTrue(SharedState.Status.connected.isOn)
        XCTAssertTrue(SharedState.Status.connecting.isOn)
        XCTAssertFalse(SharedState.Status.disconnecting.isOn)
        XCTAssertFalse(SharedState.Status.failed.isOn)
        XCTAssertFalse(SharedState.Status.disconnected.isOn)
    }
}

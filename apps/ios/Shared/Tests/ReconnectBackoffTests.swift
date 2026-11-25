// ReconnectBackoff（#1 A 真机结论 ②）：起不来的内核不被按需连接无限次拉起。

import XCTest

final class ReconnectBackoffTests: XCTestCase {
    private var suite = ""
    private var d: UserDefaults!

    override func setUp() {
        suite = "ReconnectBackoffTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    func testGeodataMissingAndMissingSubscriptionPauseImmediately() {
        let geo = ReconnectBackoff.onFailure(code: "core_crashed", message: "geodata missing: GeoSite.dat（GEOSITE 规则要用）", failures: 1)
        XCTAssertEqual(geo, .init(pause: true, retryAfter: nil))
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "subscription_invalid", message: nil, failures: 1), .init(pause: true, retryAfter: nil))
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "subscription_not_found", message: "", failures: 1), .init(pause: true, retryAfter: nil))
    }

    func testCoreCrashBacksOffThenPauses() {
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "core_crashed", message: "boom", failures: 1), .init(pause: false, retryAfter: 30))
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "core_crashed", message: "boom", failures: 2), .init(pause: false, retryAfter: 120))
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "core_crashed", message: "boom", failures: 3), .init(pause: true, retryAfter: nil))
        XCTAssertEqual(ReconnectBackoff.delay(after: 1), 30)
        XCTAssertEqual(ReconnectBackoff.delay(after: 2), 120)
        XCTAssertEqual(ReconnectBackoff.delay(after: 9), 600)
    }

    func testOtherErrorsDoNotBackOff() {
        XCTAssertEqual(ReconnectBackoff.onFailure(code: "network_unavailable", message: "x", failures: 2), .init(pause: false, retryAfter: nil))
    }

    func testGeodataPrefixOnlyAtStart() {
        XCTAssertTrue(ReconnectBackoff.isGeodataMissing("  Geodata missing: x"))
        XCTAssertFalse(ReconnectBackoff.isGeodataMissing("rules: geodata missing: x"))
        XCTAssertFalse(ReconnectBackoff.isGeodataMissing(nil))
    }

    func testWaitBeforeAuto() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ReconnectBackoff.waitBeforeAuto(.init(), now: t0), 0, "没有失败：立即")
        let one = ReconnectBackoff.Streak(failures: 1, lastAttemptAt: t0, paused: false)
        XCTAssertEqual(ReconnectBackoff.waitBeforeAuto(one, now: t0.addingTimeInterval(10)), 20)
        XCTAssertEqual(ReconnectBackoff.waitBeforeAuto(one, now: t0.addingTimeInterval(31)), 0)
        let two = ReconnectBackoff.Streak(failures: 2, lastAttemptAt: t0, paused: false)
        XCTAssertEqual(ReconnectBackoff.waitBeforeAuto(two, now: t0.addingTimeInterval(60)), 60)
        XCTAssertNil(ReconnectBackoff.waitBeforeAuto(.init(failures: 3, lastAttemptAt: t0, paused: false), now: t0.addingTimeInterval(9999)),
                     "连续 3 次：只等手动连接")
        XCTAssertNil(ReconnectBackoff.waitBeforeAuto(.init(failures: 0, lastAttemptAt: nil, paused: true), now: t0), "已暂停")
    }

    /// 尝试在 zm_start 前计数：进程中途被杀也算；连上清零；暂停写显式暂停标记，手动连接解除失败暂停。
    func testStreakPersistence() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(ReconnectBackoff.streak(in: d), .init())
        ReconnectBackoff.beginAttempt(now: t0, in: d)
        ReconnectBackoff.beginAttempt(now: t0.addingTimeInterval(40), in: d)
        let s = ReconnectBackoff.streak(in: d)
        XCTAssertEqual(s.failures, 2)
        XCTAssertEqual(s.lastAttemptAt, t0.addingTimeInterval(40))
        XCTAssertFalse(s.paused)

        ReconnectBackoff.pause(in: d)
        XCTAssertTrue(ReconnectBackoff.streak(in: d).paused)
        XCTAssertTrue(OnDemandPause.userPaused(in: d), "失败暂停与手动断开共用显式暂停：设置变化不会重新启用按需")

        ReconnectBackoff.manualStart(in: d)
        XCTAssertEqual(ReconnectBackoff.streak(in: d), .init())
    }
}

/// TunnelFailureLog（#1 ③）：扩展失败时把内核最后几行 + 原因写成 zm_logs 同格式。
final class TunnelFailureLogTests: XCTestCase {
    func testMergesCoreLogsAndFailure() throws {
        let core = #"{"seq":7,"lines":[{"seq":6,"level":"info","msg":"Can't find GeoSite.dat","at":10},{"seq":7,"level":"warning","msg":"slow","at":11}]}"#
        let b = TunnelFailureLog.make(coreLogsJSON: core, failure: "core_crashed: geodata missing: x", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(b.lines.map(\.msg), ["Can't find GeoSite.dat", "slow", "core_crashed: geodata missing: x"])
        XCTAssertEqual(b.lines.last?.level, "error")
        XCTAssertEqual(b.lines.last?.at, 1000)
        XCTAssertEqual(b.seq, 8)
    }

    func testBadCoreJSONStillRecordsFailure() {
        let b = TunnelFailureLog.make(coreLogsJSON: "not json", failure: "boom", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(b.lines.map(\.msg), ["boom"])
        XCTAssertEqual(TunnelFailureLog.make(coreLogsJSON: nil, failure: "x", at: Date()).lines.count, 1)
    }

    func testSaveLoadClear() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tfl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(TunnelFailureLog.load(from: url))
        TunnelFailureLog.save(coreLogsJSON: nil, failure: "boom", at: Date(timeIntervalSince1970: 2), to: url)
        let json = try XCTUnwrap(TunnelFailureLog.load(from: url))
        let b = try JSONDecoder().decode(TunnelFailureLog.Batch.self, from: Data(json.utf8))
        XCTAssertEqual(b.lines.map(\.msg), ["boom"])
        TunnelFailureLog.clear(at: url)
        XCTAssertNil(TunnelFailureLog.load(from: url))
    }

    /// 旧版本写的 SharedState 没有 errorMessage：照常解码为 nil；新字段往返不丢。
    func testConnectionErrorMessageIsBackwardCompatible() throws {
        let old = #"{"status":"failed","mode":"rule","errorCode":"core_crashed"}"#
        let c = try JSONDecoder().decode(SharedState.Connection.self, from: Data(old.utf8))
        XCTAssertEqual(c.errorCode, "core_crashed")
        XCTAssertNil(c.errorMessage)
        var n = c
        n.errorMessage = "geodata missing: x"
        let back = try JSONDecoder().decode(SharedState.Connection.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back.errorMessage, "geodata missing: x")
    }
}

// #1 A 真机结论（S25 Ultra，评论 7152702939）①③ 的 iOS 对应：真机不出 mock、导入后场景 / 规则即时变真、空用量是真的空、
// 连接失败原因进日志页。真 Rust 核心（模拟器），不走网络。

import XCTest
import ZephyrKit
import ZephyrMock

final class RealDeviceDataTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func engine(mockData: Bool, tunnel: (any TunnelPort)? = nil) -> CoreEngine {
        CoreEngine(dataDir: dir.appendingPathComponent("core"), fallback: MockEngine(seed: 0, clock: .live), mockData: mockData,
                   fetcher: { _ in CoreEngine.FetchedBody(body: CoreEngineTests.yaml, fileName: "Demo.yaml") }, tunnel: tunnel)
    }

    func testMockDataOnlyOnSimulatorDemoOrMissingCore() {
        // 真机（Debug / Release）且核心正常：不 mock
        XCTAssertFalse(CoreEngine.usesMockData(debug: true, simulator: false, demo: false, nativeLoaded: true))
        XCTAssertFalse(CoreEngine.usesMockData(debug: false, simulator: false, demo: false, nativeLoaded: true))
        // Debug 模拟器：空库用 mock 顶上
        XCTAssertTrue(CoreEngine.usesMockData(debug: true, simulator: true, demo: false, nativeLoaded: true))
        // 演示模式总是
        XCTAssertTrue(CoreEngine.usesMockData(debug: false, simulator: false, demo: true, nativeLoaded: true))
        // 核心没加载起来：只有 Debug
        XCTAssertTrue(CoreEngine.usesMockData(debug: true, simulator: false, demo: false, nativeLoaded: false))
        XCTAssertFalse(CoreEngine.usesMockData(debug: false, simulator: false, demo: false, nativeLoaded: false))
        // Release 模拟器也不 mock
        XCTAssertFalse(CoreEngine.usesMockData(debug: false, simulator: true, demo: false, nativeLoaded: true))
    }

    func testUsageTodayIsRealEmptyWithoutMock() async {
        let e = engine(mockData: false)
        XCTAssertFalse(e.usesMockData)
        let u = await e.usageToday()
        XCTAssertEqual(u.todayBytes, 0)
        XCTAssertEqual(u.onlineMillisToday, 0)
        XCTAssertEqual(u.regionsToday, 0)
        XCTAssertNil(u.fastestLatencyMs)
        XCTAssertEqual(u.hourly, Array(repeating: 0, count: 24))
    }

    /// mock 兜底时：空库先出 mock 场景，导入订阅后不重启就换成真实场景（此前 mock 只判断一次，永远停在假数据）。
    func testScenesSwitchFromMockToRealAfterImport() async throws {
        let e = engine(mockData: true)
        let first = await withDeadline(5) { () async -> [ZephyrKit.Scene]? in
            for await v in e.scenes() { return v }
            return nil
        }
        let mock = try XCTUnwrap(first)
        XCTAssertFalse(mock.isEmpty, "空库 + mock 兜底：先给演示场景")
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let real = await withDeadline(10) { () async -> [ZephyrKit.Scene]? in
            for await v in e.scenes() where v != mock { return v }
            return nil
        }
        XCTAssertNotNil(real, "导入后应换成核心的真实场景")
    }

    /// 无 mock：空库给空场景，导入后出真实场景，删光后又回到空（不残留旧的“就绪”缓存）。
    func testScenesAndRulesFollowLibraryWithoutMock() async throws {
        let e = engine(mockData: false)
        let first = await withDeadline(5) { () async -> [ZephyrKit.Scene]? in
            for await v in e.scenes() { return v }
            return nil
        }
        XCTAssertEqual(first, [])
        let empty = await e.ruleStats()
        XCTAssertEqual(empty.total, 0, "空库：规则为空（不缓存这个否定结果）")

        let sub = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let rules = await e.ruleStats()
        XCTAssertGreaterThan(rules.total, 0, "导入后规则页立即有数")
        let got = await withDeadline(10) { () async -> [ZephyrKit.Scene]? in
            for await v in e.scenes() where !v.isEmpty { return v }
            return nil
        }
        XCTAssertNotNil(got, "导入后出真实场景")

        try await e.deleteSubscription(id: sub.id)
        let after = await e.ruleStats()
        XCTAssertEqual(after.total, 0, "删光订阅后规则页不能还停在旧的就绪缓存")
    }

    func testAppLogReachesLogsStreamWithoutTunnel() async throws {
        let e = engine(mockData: false)
        e.appLog(.error, CoreEngine.failureLine(ZephyrError(code: .coreCrashed, message: "geodata missing: GeoSite.dat")))
        e.appLog(.info, "below threshold")
        let collected = Task { () -> [LogLine] in
            var out: [LogLine] = []
            for await l in e.logs(minLevel: .warning) { out.append(l); if out.count >= 2 { break } }
            return out
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        e.appLog(.warning, "later")
        let lines = await withDeadline(5) { await collected.value } ?? []
        XCTAssertEqual(lines.first?.level, .error)
        XCTAssertEqual(lines.first?.message, "connect failed (core_crashed): geodata missing: GeoSite.dat")
        XCTAssertEqual(lines.dropFirst().first?.message, "later", "之后的行实时推送，低于级别的被滤掉")
    }

    /// 真机路径：扩展写下的失败日志（内核最后几行 + 原因）和隧道 failed 状态的原因都进日志页。
    func testTunnelFailureReachesLogs() async throws {
        let t = FailingTunnel(dir: dir)
        let e = engine(mockData: false, tunnel: t)
        var states = e.connectionState().makeAsyncIterator()
        let s = await states.next()
        XCTAssertEqual(s?.status, .failed)
        XCTAssertEqual(s?.error?.message, "geodata missing: GeoSite.dat")

        let collected = Task { () -> [String] in
            var out: [String] = []
            for await l in e.logs(minLevel: .info) { out.append(l.message); if out.count >= 3 { break } }
            return out
        }
        let lines = await withDeadline(8) { await collected.value } ?? []
        XCTAssertTrue(lines.contains("Can't find GeoSite.dat, start download"), "\(lines)")
        XCTAssertTrue(lines.contains("core_crashed: geodata missing: GeoSite.dat"), "\(lines)")
        XCTAssertTrue(lines.contains("connect failed (core_crashed): geodata missing: GeoSite.dat"), "\(lines)")
    }
}

/// 启动失败过的隧道：状态 failed（带原文），留有失败日志。
final class FailingTunnel: TunnelPort, @unchecked Sendable {
    let configURL: URL
    let controllerSocketPath: String
    init(dir: URL) {
        configURL = dir.appendingPathComponent("tunnel/config.yaml")
        controllerSocketPath = dir.appendingPathComponent("none.sock").path
    }
    func states() -> AsyncStream<ConnectionState> {
        let s = ConnectionState(status: .failed, mode: .rule,
                                error: ZephyrError(code: .coreCrashed, message: "geodata missing: GeoSite.dat"))
        return AsyncStream { $0.yield(s) }   // 不 finish：与真机一样一直订阅
    }
    func start() async throws {}
    func stop() async throws {}
    func setMode(_ mode: ZephyrKit.ProxyMode) async throws {}
    func rate() async -> (up: Int64, down: Int64)? { nil }
    func reloadConfig() async throws {}
    func urlTest(proxiesJSON: String, url: String, timeoutMs: Int32) async -> String? { nil }
    func usageToday() async -> (hourly: [Int64], onlineMillis: Int64)? { nil }
    func logs(since: Int64, minLevel: String, limit: Int32) async -> String? { nil }
    func failureLogs() async -> String? {
        #"{"seq":2,"lines":[{"seq":1,"level":"info","msg":"Can't find GeoSite.dat, start download","at":1},{"seq":2,"level":"error","msg":"core_crashed: geodata missing: GeoSite.dat","at":2}]}"#
    }
}

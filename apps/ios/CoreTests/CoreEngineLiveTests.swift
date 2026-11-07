// CoreEngine 实时部分：经 TunnelPort 的连接 / 模式 / 流量；控制口不可达时给空而不抛。
// 用假的 TunnelPort，不需要 NetworkExtension；MihomoClient 指向不存在的 socket。

import XCTest
import ZephyrKit

final class FakeTunnel: TunnelPort, @unchecked Sendable {
    let lock = NSLock()
    var started = 0, stopped = 0, reloads = 0
    var mode: ZephyrKit.ProxyMode = .rule
    var status: ConnectionStatus = .disconnected
    let configURL: URL
    let controllerSocketPath: String

    init(dir: URL) {
        configURL = dir.appendingPathComponent("tunnel/config.yaml")
        controllerSocketPath = dir.appendingPathComponent("none.sock").path
    }

    func states() -> AsyncStream<ConnectionState> {
        let s = lock.withLock { ConnectionState(status: status, mode: mode) }
        return AsyncStream { $0.yield(s); $0.finish() }
    }
    func start() async throws { lock.withLock { started += 1; status = .connected } }
    func stop() async throws { lock.withLock { stopped += 1; status = .disconnected } }
    func setMode(_ m: ZephyrKit.ProxyMode) async throws { lock.withLock { mode = m } }
    func rate() async -> (up: Int64, down: Int64)? { lock.withLock { status == .connected ? (10, 2048) : nil } }
    func reloadConfig() async throws { lock.withLock { reloads += 1 } }
}

final class CoreEngineLiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func make() -> (CoreEngine, FakeTunnel) {
        let t = FakeTunnel(dir: dir)
        let e = CoreEngine(dataDir: dir.appendingPathComponent("core"), mockData: false, fetcher: { _ in
            CoreEngine.FetchedBody(body: CoreEngineTests.yaml, fileName: "Demo.yaml")
        }, tunnel: t)
        return (e, t)
    }

    func testConnectWritesConfigThenStartsTunnel() async throws {
        let (e, t) = make()
        do { try await e.connect(); XCTFail("无订阅不能连接") } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .subscriptionInvalid)
        }
        XCTAssertEqual(t.started, 0)
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        try await e.connect()
        XCTAssertEqual(t.started, 1)
        let yaml = try String(contentsOf: t.configURL, encoding: .utf8)
        XCTAssertTrue(yaml.contains("file-descriptor: -1"))
        XCTAssertTrue(yaml.contains(t.controllerSocketPath))
        var it = e.connectionState().makeAsyncIterator()
        let st = await it.next()
        XCTAssertEqual(st?.status, .connected)
        try await e.disconnect()
        XCTAssertEqual(t.stopped, 1)
    }

    func testModeGoesToTunnel() async throws {
        let (e, t) = make()
        try await e.setMode(mode: .global)
        XCTAssertEqual(t.mode, .global)
    }

    func testTrafficFromTunnelAndRecentBuffer() async throws {
        let (e, _) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        try await e.connect()
        var it = e.traffic().makeAsyncIterator()
        let s = await it.next()
        XCTAssertEqual(s?.downBps, 2048)
        XCTAssertEqual(s?.upBps, 10)
        XCTAssertEqual(e.recentTraffic(seconds: 60).count, 1)
    }

    func testUnreachableControllerYieldsEmpty() async throws {
        let (e, _) = make()
        var groups = e.policyGroups().makeAsyncIterator()
        let g = await groups.next()
        XCTAssertEqual(g, [])
        var conns = e.activeConnections().makeAsyncIterator()
        let c = await conns.next()
        XCTAssertEqual(c, [])
        do { _ = try await e.groupMembers(group: "Proxy", offset: 0, limit: 10); XCTFail("控制口不可达应抛") } catch {}
    }

    func testSubscriptionUpdateReloadsRunningTunnel() async throws {
        let (e, t) = make()
        let sub = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        _ = try await e.updateSubscription(id: sub.id)
        XCTAssertEqual(t.reloads, 0, "未连接不重载")
        try await e.connect()
        _ = try await e.updateSubscription(id: sub.id)
        XCTAssertEqual(t.reloads, 1)
    }

    func testOverrideHostReloadsRunningTunnelAndLandsInConfig() async throws {
        let (e, t) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        try await e.connect()
        try await e.overrideHost(host: "corp.example.com", target: .direct, sceneId: nil, persistent: true)
        XCTAssertEqual(t.reloads, 1)
        let yaml = try String(contentsOf: t.configURL, encoding: .utf8)
        XCTAssertTrue(yaml.contains("corp.example.com,DIRECT"), yaml)
        try await e.overrideHost(host: "corp.example.com", target: .unchanged, sceneId: nil, persistent: true)
        XCTAssertFalse(try String(contentsOf: t.configURL, encoding: .utf8).contains("corp.example.com"))
    }

    func testSetSceneSourceRecordsSource() async throws {
        let (e, _) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        try await e.setSceneSource(sceneId: "video", source: .manual)
        var it = e.scenes().makeAsyncIterator()
        let v = await it.next()?.first { $0.id == "video" }
        XCTAssertEqual(v?.source, .manual)
        XCTAssertEqual(v?.services, [])
    }

    func testRetestWithoutTunnelReturnsCache() async throws {
        let (e, _) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let s = try await e.retestScene(sceneId: "ai")
        XCTAssertEqual(s.id, "ai")
        XCTAssertNil(s.testedAt, "隧道没在跑不探测")
    }

    func testLocalProxyOptions() throws {
        let d = UserDefaults(suiteName: "lp-\(UUID().uuidString)")!
        var s = ZephyrKit.Settings(onDemand: true, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890,
                                   localProxyAuth: false, testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12,
                                   updateOnWifiOnly: true, showChangesBeforeUpdate: true, dns: DnsSettings(), tun: TunSettings(),
                                   accent: .blue, appearance: .system, shareAnonymousPattern: true)
        XCTAssertNil(CoreEngine.localProxy(settings: s, defaults: d), "默认关")
        s.localProxyEnabled = true
        s.localProxyPort = 7890
        s.localProxyAuth = true
        let lp = try XCTUnwrap(CoreEngine.localProxy(settings: s, defaults: d))
        XCTAssertEqual(lp.port, 7890)
        XCTAssertEqual(lp.auth, CoreEngine.localProxyCredential(defaults: d), "凭据稳定")
        XCTAssertTrue(lp.auth!.hasPrefix("zephyr:"))
        s.localProxyAuth = false
        XCTAssertNil(CoreEngine.localProxy(settings: s, defaults: d)?.auth)
        s.localProxyPort = 80
        XCTAssertNil(CoreEngine.localProxy(settings: s, defaults: d), "特权端口拒绝")
    }

    func testMemberIdIsStable() {
        XCTAssertEqual(CoreEngine.memberId(group: "Proxy", name: "香港 01"), CoreEngine.memberId(group: "Proxy", name: "香港 01"))
        XCTAssertNotEqual(CoreEngine.memberId(group: "Proxy", name: "香港 01"), CoreEngine.memberId(group: "Video", name: "香港 01"))
        XCTAssertNotEqual(CoreEngine.memberId(group: "ab", name: "c"), CoreEngine.memberId(group: "a", name: "bc"))
    }
}

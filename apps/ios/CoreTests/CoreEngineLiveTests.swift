// CoreEngine 实时部分：经 TunnelPort 的连接 / 模式 / 流量；控制口不可达时给空而不抛。
// 用假的 TunnelPort，不需要 NetworkExtension；MihomoClient 指向不存在的 socket。

import XCTest
import Network
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
    func usageToday() async -> (hourly: [Int64], onlineMillis: Int64)? {
        var h = Array(repeating: Int64(0), count: 24); h[9] = 1_000; h[10] = 500
        return (h, 7_200_000)
    }
    var logCalls = 0
    func logs(since: Int64, minLevel: String, limit: Int32) async -> String? {
        lock.withLock { logCalls += 1 }
        return since == 0 ? #"{"seq":2,"lines":[{"seq":1,"level":"warning","msg":"dial timeout","at":5},{"seq":2,"level":"error","msg":"x","at":6}]}"# : #"{"seq":2,"lines":[]}"#
    }
    var urlTestInputs: [String] = []
    func urlTest(proxiesJSON: String, url: String, timeoutMs: Int32) async -> String? {
        let connected = lock.withLock { () -> Bool in urlTestInputs.append(proxiesJSON); return status == .connected }
        guard connected, let data = proxiesJSON.data(using: .utf8),
              let defs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        // 假结果：每个 37 ms
        let results = defs.compactMap { $0["name"] as? String }.map { #"{"name":"\#($0)","ms":37}"# }
        return #"{"results":["# + results.joined(separator: ",") + "]}"
    }
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

    func testLatencyViaTunnelRecordsAndStreams() async throws {
        let (e, t) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let q = try await e.queryNodes(query: "")
        let page = try await e.nodeRows(token: q.token, offset: 0, limit: 10)
        let ids = page.rows.map(\.id)
        XCTAssertFalse(ids.isEmpty)
        await e.testLatency(ids: ids)
        XCTAssertTrue(t.urlTestInputs.isEmpty, "未连接不走扩展（改测 TCP 握手）")
        try await e.connect()
        var it = e.latencyUpdates().makeAsyncIterator()
        await e.testLatency(ids: ids + ids)
        XCTAssertEqual(t.urlTestInputs.count, 1, "去重后一批")
        let ups = await it.next()
        XCTAssertEqual(Set(ups?.map(\.id) ?? []), Set(ids))
        XCTAssertEqual(ups?.first?.latencyMs, 37)
        let idx = await e.nodeIndex()
        XCTAssertEqual(idx.testedCount, Int64(ids.count))
        let d = try await e.node(id: ids[0])
        XCTAssertEqual(d.summary.id, ids[0])
        XCTAssertEqual(d.summary.latencyMs, 37)
        XCTAssertTrue(d.server.contains("*"), d.server)
        XCTAssertFalse(t.urlTestInputs[0].isEmpty)
    }

    func testNodeDetailUnknownThrows() async throws {
        let (e, _) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        do { _ = try await e.node(id: 0xdead); XCTFail("应抛 nodeNotFound") } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .nodeNotFound)
        }
    }

    func testSettingsPersistAndReloadOnRuntimeChange() async throws {
        let (e, t) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        var it = e.settings().makeAsyncIterator()
        let first = await it.next()
        var s = try XCTUnwrap(first)
        XCTAssertEqual(s, CoreEngine.defaultSettings)
        try await e.connect()
        s.appearance = .dark
        try await e.updateSettings(patch: s)
        XCTAssertEqual(t.reloads, 0, "外观不影响 mihomo")
        s.localProxyEnabled = true
        try await e.updateSettings(patch: s)
        XCTAssertEqual(t.reloads, 1)
        XCTAssertTrue(try String(contentsOf: t.configURL, encoding: .utf8).contains("mixed-port: 7890"))
        let latest = await it.next()
        XCTAssertEqual(latest?.appearance, .dark)
        // 新实例读回
        let e2 = CoreEngine(dataDir: dir.appendingPathComponent("core"), mockData: false)
        var it2 = e2.settings().makeAsyncIterator()
        let reread = await it2.next()
        XCTAssertEqual(reread, s)
        s.tun.mtu = 100
        do { try await e.updateSettings(patch: s); XCTFail("非法 MTU") } catch {}
    }

    func testLogsFromTunnel() async throws {
        let (e, _) = make()
        var it = e.logs(minLevel: .warning).makeAsyncIterator()
        let a = await it.next(), b = await it.next()
        XCTAssertEqual(a, LogLine(at: 5, level: .warning, message: "dial timeout"))
        XCTAssertEqual(b?.level, .error)
    }

    func testGlobalNodeReloadsAndLandsInConfig() async throws {
        let (e, t) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let q = try await e.queryNodes(query: "")
        let id = try await e.nodeRows(token: q.token, offset: 0, limit: 1).rows[0].id
        try await e.connect()
        let x = try await e.setGlobalNode(id: id)
        XCTAssertNil(x.sceneId)
        XCTAssertFalse(x.affectedApps.isEmpty)
        XCTAssertEqual(t.reloads, 1)
        _ = try await e.setGlobalNode(id: id)
        XCTAssertEqual(t.reloads, 1, "已在配置里不重载")
    }

    func testUsageTodayFromLedger() async throws {
        let (e, _) = make()
        let u = await e.usageToday()
        XCTAssertEqual(u.todayBytes, 1_500)
        XCTAssertEqual(u.hourly.count, 24)
        XCTAssertEqual(u.onlineMillisToday, 7_200_000)
        XCTAssertEqual(u.regionsToday, 0)
    }

    func testCommandSuggestionsReal() async throws {
        let (e, _) = make()
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/a")
        let empty = await e.commandSuggestions(input: "")
        XCTAssertEqual(empty.first?.kind, .toggleConnection)
        XCTAssertTrue(empty.contains { $0.kind == .openPage && $0.subtitle == "1 个订阅" })
        let host = await e.commandSuggestions(input: "example.com")
        XCTAssertEqual(host.first?.kind, .testRule)
        XCTAssertEqual(host.first?.subtitle, "第 2 层 → 直连", "\(host)")
        let mode = await e.commandSuggestions(input: "全局")
        XCTAssertTrue(mode.contains { $0.kind == .switchMode && $0.payload == "global" })
        let hk = await e.commandSuggestions(input: "香港")
        XCTAssertTrue(hk.contains { $0.kind == .openNodeQuery }, "\(hk)")
        XCTAssertLessThanOrEqual(hk.count, 8)
        XCTAssertTrue(CoreEngine.looksLikeHost("1.2.3.4") && CoreEngine.looksLikeHost("2001:db8::1") && !CoreEngine.looksLikeHost("香港 iplc"))
    }

    func testRuleProvidersFetchedAndCompiled() async throws {
        let sub = """
        proxies:
          - {name: a, server: a.example, port: 443, type: trojan, password: p}
        rule-providers:
          openai: {type: http, behavior: domain, url: 'https://rules.example/openai.yaml', interval: 86400}
        rules:
          - RULE-SET,openai,a
          - MATCH,DIRECT
        """
        let e = CoreEngine(dataDir: dir.appendingPathComponent("core"), mockData: false, fetcher: { url in
            url.host == "rules.example" ? CoreEngine.FetchedBody(body: "payload:\n  - '+.openai.com'\n") : CoreEngine.FetchedBody(body: sub, fileName: "S.yaml")
        })
        _ = try await e.importSubscription(source: .url, payload: "https://sub.example.com/s")
        let n = await e.refreshRuleProviders(force: true)
        XCTAssertEqual(n, 1)
        let t = try await e.testRule(input: "api.openai.com")
        XCTAssertEqual(t.layerIndex, 2)
        XCTAssertEqual(t.policy, "a")
        let st = await e.ruleStats()
        XCTAssertEqual(st.layers.count, 3)
    }

    /// states() 永不出值时 currentStatus 不挂起，按 disconnected 处理（热重载不会卡住订阅更新）。
    func testCurrentStatusDoesNotHang() async {
        final class Silent: TunnelPort, @unchecked Sendable {
            let configURL = URL(fileURLWithPath: "/dev/null")
            let controllerSocketPath = "/nonexistent.sock"
            func states() -> AsyncStream<ConnectionState> { AsyncStream { _ in } }
            func start() async throws {}
            func stop() async throws {}
            func setMode(_ mode: ZephyrKit.ProxyMode) async throws {}
            func rate() async -> (up: Int64, down: Int64)? { nil }
            func reloadConfig() async throws {}
            func urlTest(proxiesJSON: String, url: String, timeoutMs: Int32) async -> String? { nil }
            func usageToday() async -> (hourly: [Int64], onlineMillis: Int64)? { nil }
            func logs(since: Int64, minLevel: String, limit: Int32) async -> String? { nil }
        }
        let t0 = Date()
        let st = await Silent().currentStatus()
        XCTAssertEqual(st, .disconnected)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5)
        let f = FakeTunnel(dir: dir)
        f.status = .connected
        let st2 = await f.currentStatus()
        XCTAssertEqual(st2, .connected)
    }

    /// 未连接时的 TCP 握手测速：本机监听端口可测出耗时，无人监听的端口为 -1。
    func testTcpHandshake() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { c in c.start(queue: .global()); c.cancel() }
        let ready = expectation(description: "listener")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port?.rawValue)
        let ms = await CoreEngine.tcpHandshake(host: "127.0.0.1", port: port)
        XCTAssertGreaterThanOrEqual(ms, 1)
        listener.cancel()
        let closed = await CoreEngine.tcpHandshake(host: "127.0.0.1", port: 1, timeout: 2)
        XCTAssertEqual(closed, -1)
    }

    func testMemberIdIsStable() {
        XCTAssertEqual(CoreEngine.memberId(group: "Proxy", name: "香港 01"), CoreEngine.memberId(group: "Proxy", name: "香港 01"))
        XCTAssertNotEqual(CoreEngine.memberId(group: "Proxy", name: "香港 01"), CoreEngine.memberId(group: "Video", name: "香港 01"))
        XCTAssertNotEqual(CoreEngine.memberId(group: "ab", name: "c"), CoreEngine.memberId(group: "a", name: "bc"))
    }
}

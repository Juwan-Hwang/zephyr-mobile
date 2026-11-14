import XCTest
import ZephyrKit
@testable import ZephyrMock

final class EngineTests: XCTestCase {
    let sh = TimeZone(identifier: "Asia/Shanghai")!

    func first<T>(_ s: AsyncStream<T>) async -> T? { for await v in s { return v }; return nil }

    func testFrozen941Connection() async {
        let e = MockEngine(clock: .frozen941)
        let st = await first(e.connectionState())!
        XCTAssertEqual(st.status, .connected)
        XCTAssertEqual(st.mode, .rule)
        XCTAssertEqual(ZFormat.duration(e.clock.now() - st.since!), "2:14:07")
        XCTAssertEqual(ZFormat.clock(e.clock.now(), timeZone: sh), "9:41")
        let t = await first(e.traffic())!
        XCTAssertEqual(ZFormat.rateString(t.downBps), "2.8 MB/s")
        XCTAssertEqual(ZFormat.rateString(t.upBps), "194 KB/s")
        let recent = e.recentTraffic(seconds: 60)
        XCTAssertEqual(recent.count, 60)
        XCTAssertEqual(recent.last, t)
        XCTAssertEqual(e.recentTraffic(seconds: 1000).count, 300)
    }

    func testLiveConnectDisconnect() async throws {
        let e = MockEngine(clock: .live)
        do { let v = await first(e.connectionState())?.status; XCTAssertEqual(v, .disconnected) }
        XCTAssertTrue(e.recentTraffic(seconds: 10).isEmpty)
        let stream = e.connectionState()
        // 单调时钟只断言下限（Mock 用 Task.sleep 模拟握手），不对上限计时，避免 CI 机器负载抖动（REVIEW-Q2 P2）。
        let clock = ContinuousClock()
        let t0 = clock.now
        try await e.connect()
        XCTAssertGreaterThanOrEqual(clock.now - t0, .milliseconds(550))
        var seen: [ConnectionStatus] = []
        for await s in stream { seen.append(s.status); if s.status == .connected { break } }
        XCTAssertEqual(seen, [.disconnected, .connecting, .connected])
        let conns = await first(e.activeConnections())!
        XCTAssertFalse(conns.isEmpty)
        XCTAssertEqual(conns.first { $0.host == "claude.ai" }?.node, "US-Fixed-01")
        try await e.disconnect()
        do { let v = await first(e.connectionState())?.status; XCTAssertEqual(v, .disconnected) }
        do { let v = await first(e.activeConnections())!.isEmpty; XCTAssertTrue(v) }
    }

    func testTrafficDeterministicRanges() {
        for t in Int64(1_793_900_000)..<Int64(1_793_920_000) {
            let s = MockFixtures.traffic(second: t, seed: 0)
            XCTAssertTrue((2_400_000...3_400_000).contains(s.downBps), "\(s.downBps)")
            XCTAssertTrue((150_000...260_000).contains(s.upBps), "\(s.upBps)")
        }
        XCTAssertEqual(MockFixtures.traffic(second: 42, seed: 7), MockFixtures.traffic(second: 42, seed: 7))
    }

    func testModeAndGlobal() async throws {
        let e = MockEngine(clock: .frozen941)
        try await e.setMode(mode: .global)
        let s = await first(e.connectionState())!
        XCTAssertEqual(s.mode, .global)
        XCTAssertEqual(s.globalNodeId, MockFixtures.tk03.summary.id)
        let change = try await e.setGlobalNode(id: MockFixtures.sg02.summary.id)
        XCTAssertEqual(change.fromRegion, "JP"); XCTAssertEqual(change.fromIp, "203.0.113.61")
        XCTAssertEqual(change.toRegion, "SG"); XCTAssertEqual(change.toIp, "198.51.100.7")
        XCTAssertNil(change.sceneId)
        do { _ = try await e.setGlobalNode(id: 99_999_999_999); XCTFail() } catch let err as ZephyrError { XCTAssertEqual(err.code, .nodeNotFound) }
    }

    func testScenes() async throws {
        let e = MockEngine(clock: .frozen941)
        let scenes = await first(e.scenes())!
        XCTAssertEqual(scenes.map(\.id), ["ai", "video", "other"])
        let ai = scenes[0], video = scenes[1], other = scenes[2]
        XCTAssertEqual(ai.name, "AI"); XCTAssertEqual(ai.available, 9)
        XCTAssertEqual(ai.selected.region, "SG"); XCTAssertEqual(ai.selected.name, "新加坡 02"); XCTAssertEqual(ai.exitIp, "198.51.100.7")
        XCTAssertEqual(ai.exceptions.first?.app, "Claude"); XCTAssertEqual(ai.exceptions.first?.node.name, "US-Fixed-01")
        XCTAssertEqual(video.name, "视频"); XCTAssertEqual(video.available, 22); XCTAssertEqual(video.selected.name, "香港 HKT")
        XCTAssertEqual(video.exitIp, "203.0.113.24"); XCTAssertEqual(video.note, "Netflix 完整片库")
        XCTAssertEqual(other.name, "其他"); XCTAssertEqual(other.selected.name, "TW-Fixed-01"); XCTAssertEqual(other.exitIp, "198.51.100.41")
        XCTAssertEqual(other.source, .subscriptionGroup)
        XCTAssertEqual(ZFormat.relative(ai.testedAt!, now: e.clock.now()), "2 小时前")

        let jp = try await e.sceneCandidates(sceneId: "ai", region: "JP")
        XCTAssertEqual(jp.map(\.name), ["东京 03", "东京 07", "大阪 01"])
        let all = try await e.sceneCandidates(sceneId: "ai", region: nil)
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.map { $0.latencyMs! }, all.map { $0.latencyMs! }.sorted())
        do { let v = try await e.sceneCandidates(sceneId: "video", region: nil).count; XCTAssertEqual(v, 22) }

        let tk03 = jp[0].id
        let change = try await e.previewSceneChange(sceneId: "ai", nodeId: tk03)
        XCTAssertEqual(change.sceneId, "ai")
        XCTAssertEqual(change.fromRegion, "SG"); XCTAssertEqual(change.fromIp, "198.51.100.7")
        XCTAssertEqual(change.toRegion, "JP"); XCTAssertEqual(change.toIp, "203.0.113.61")
        XCTAssertEqual(change.affectedApps, ["GPT", "Gemini"]); XCTAssertEqual(change.unchangedApps, ["Claude"])

        let stream = e.scenes()
        try await e.applySceneChange(sceneId: "ai", nodeId: tk03)
        var it = stream.makeAsyncIterator()
        _ = await it.next()
        let updated = await it.next()!
        XCTAssertEqual(updated[0].selected.name, "东京 03"); XCTAssertEqual(updated[0].exitIp, "203.0.113.61")
        // 撤销
        try await e.applySceneChange(sceneId: "ai", nodeId: MockFixtures.sg02.summary.id)
        do { let v = await first(e.scenes())![0].exitIp; XCTAssertEqual(v, "198.51.100.7") }
        let re = try await e.retestScene(sceneId: "video")
        XCTAssertEqual(re.testedAt, e.clock.now())
        do { _ = try await e.retestScene(sceneId: "nope"); XCTFail() } catch let err as ZephyrError { XCTAssertEqual(err.code, .sceneNotFound) }
    }

    func testUsageSubscriptionsStorageSettings() async throws {
        let e = MockEngine(clock: .frozen941)
        let now = e.clock.now()
        let u = await e.usageToday()
        XCTAssertEqual(ZFormat.bytes(u.todayBytes), "1.8 GB")
        XCTAssertEqual(u.regionsToday, 4); XCTAssertEqual(u.onlineMillisToday, 6 * 3_600_000); XCTAssertEqual(u.fastestLatencyMs, 38)
        XCTAssertEqual(u.hourly.count, 24); XCTAssertEqual(u.hourly.reduce(0, +), 1_800_000_000)

        let summary = await e.subscriptionsSummary()
        XCTAssertEqual(summary.count, 214); XCTAssertEqual(summary.totalNodes, 13_109_802)
        let subs = await first(e.subscriptions())!
        XCTAssertEqual(subs.dropFirst(2).reduce(0) { $0 + $1.nodeCount }, 13_098_480)
        XCTAssertTrue(subs.allSatisfy { $0.nodeCount > 0 && $0.autoUpdateHours == 12 })
        let neb = subs[0], orb = subs[1]
        XCTAssertEqual(neb.name, "Nebula Cloud"); XCTAssertEqual(ZFormat.count(neb.nodeCount), "8,204")
        XCTAssertEqual(ZFormat.bytes(neb.remainingBytes!), "86.4 GB")
        XCTAssertEqual(ZFormat.expiry(neb.expiresAt!, now: now, timeZone: sh), "26 天后到期")
        XCTAssertEqual(ZFormat.relative(neb.updatedAt!, now: now), "2 小时前")
        XCTAssertEqual(neb.lastDiff, SubscriptionDiff(addedNodes: 1204, removedNodes: 318, ruleChanges: 0, overridesKept: true, scenesRetested: true))
        XCTAssertEqual(orb.name, "Orbit"); XCTAssertEqual(orb.nodeCount, 3118)
        XCTAssertEqual(ZFormat.bytes(orb.remainingBytes!), "12.0 GB")
        XCTAssertEqual(ZFormat.expiry(orb.expiresAt!, now: now, timeZone: sh), "11月9日到期")

        let d = try await e.previewUpdate(id: "nebula"); XCTAssertEqual(d.addedNodes, 1204)
        _ = try await e.updateSubscription(id: "orbit")
        let imported = try await e.importSubscription(source: .url, payload: "https://new.example.com/sub?token=abc")
        XCTAssertEqual(imported.name, "new.example.com")
        do { let v = await e.subscriptionsSummary().count; XCTAssertEqual(v, 215) }
        try await e.deleteSubscription(id: imported.id)
        do { let v = await e.subscriptionsSummary().count; XCTAssertEqual(v, 214) }
        do { _ = try await e.importSubscription(source: .clipboard, payload: "hello"); XCTFail() }
        catch let err as ZephyrError { XCTAssertEqual(err.code, .subscriptionInvalid) }
        // 契约 §15：桌面"同步到手机"二维码
        let synced = try await e.importSubscription(source: .qr, payload: "zephyr://import?url=https%3A%2F%2Fa.example.com%2Fs&name=Nebula%20Sync&auto=6")
        XCTAssertEqual(synced.name, "Nebula Sync")
        try await e.deleteSubscription(id: synced.id)
        do { _ = try await e.importSubscription(source: .qr, payload: "zephyr://import?v=2&url=https%3A%2F%2Fa.example.com"); XCTFail("新版本导入码应拒绝") }
        catch let err as ZephyrError { XCTAssertEqual(err.code, .subscriptionInvalid) }
        do { let v = try await e.updateAll().count; XCTAssertEqual(v, 214) }

        let st = await e.storage()
        XCTAssertEqual([st.nodesBytes, st.rulesBytes, st.freeBytes].map(ZFormat.bytes), ["600 MB", "1.9 GB", "3.1 GB"])
        var s = await first(e.settings())!
        XCTAssertEqual(s.trustedWifi, ["家"]); XCTAssertEqual(s.localProxyPort, 7890); XCTAssertFalse(s.localProxyAuth)
        XCTAssertTrue(s.testOnWifiOnly); XCTAssertEqual(s.latencyTtlHours, 24); XCTAssertEqual(s.autoUpdateHours, 12)
        XCTAssertTrue(s.updateOnWifiOnly); XCTAssertTrue(s.showChangesBeforeUpdate); XCTAssertEqual(s.accent, .blue); XCTAssertEqual(s.appearance, .system)
        s.accent = .pink
        try await e.updateSettings(patch: s)
        do { let v = await first(e.settings())!.accent; XCTAssertEqual(v, .pink) }
    }

    func testIndexAndLatency() async throws {
        let e = MockEngine(clock: .frozen941)
        let idx = await e.nodeIndex()
        XCTAssertEqual(idx.total, 13_109_802); XCTAssertEqual(idx.sections.count, 15); XCTAssertEqual(idx.testedCount, 41_280)
        XCTAssertEqual(idx.sections[1].rowOffset, 1 + 3_118_402)

        let res = try await e.queryNodes(query: "jp")
        let page = try await e.nodeRows(token: res.token, offset: 0, limit: 100)
        let untested = page.rows.filter { $0.latencyMs == nil }.map(\.id)
        XCTAssertFalse(untested.isEmpty)
        let updates = e.latencyUpdates()
        await e.testLatency(ids: page.rows.map(\.id))
        var it = updates.makeAsyncIterator()
        let batch = await it.next()!
        XCTAssertEqual(batch.count, 100)
        for u in batch {
            let (r, j) = MockNodes.split(u.id)!
            XCTAssertEqual(u.latencyMs, MockNodes.measuredLatency(r, j))
            if let c = MockNodes.cachedLatency(r, j) { XCTAssertEqual(u.latencyMs, c) }
        }
        let after = try await e.nodeRows(token: res.token, offset: 0, limit: 100)
        XCTAssertTrue(after.rows.allSatisfy { $0.latencyMs != nil })
        do { let v = await e.nodeIndex().testedCount; XCTAssertEqual(v, 41_280 + 100) }
        // 超时 -1 的确存在于样本空间
        let timeouts = (Int64(0)..<5000).filter { MockNodes.measuredLatency(1, $0) == -1 }
        XCTAssertFalse(timeouts.isEmpty)
        do { _ = try await e.nodeRows(token: 987_654, offset: 0, limit: 1); XCTFail() } catch {}
        let empty = try await e.queryNodes(query: "jp hkt")
        XCTAssertEqual(empty.total, 0); XCTAssertTrue(empty.sections.isEmpty)
        do { let v = try await e.queryNodes(query: "东京 iplc").highlights; XCTAssertEqual(v, ["东京", "IPLC"]) }
    }

    func testLiveLatencyIsDelayed() async {
        let e = MockEngine(clock: .live)
        let updates = e.latencyUpdates()
        let clock = ContinuousClock()
        let t0 = clock.now
        await e.testLatency(ids: [MockNodes.id(2, 1), MockNodes.id(2, 2), MockNodes.id(2, 3)])
        var got = 0
        for await b in updates { got += b.count; if got >= 3 { break } }
        let dt = clock.now - t0
        // 下限证明结果确实延迟到达；上限只防挂死，留足 CI 余量（原 1 s 在排队机器上偶发失败）。
        XCTAssertGreaterThanOrEqual(dt, .milliseconds(80)); XCTAssertLessThan(dt, .seconds(10))
    }

    func testGroups() async throws {
        let e = MockEngine(clock: .frozen941)
        let groups = await first(e.policyGroups())!
        XCTAssertEqual(groups.map(\.type), [.select, .urlTest, .fallback, .loadBalance, .select, .select])
        let page = try await e.groupMembers(group: "自动选择", offset: 490, limit: 500)
        XCTAssertEqual(page.total, 500); XCTAssertEqual(page.rows.count, 10)
        XCTAssertTrue(page.rows.allSatisfy { $0.tag == "IPLC" })
        try await e.selectInGroup(group: "香港", nodeId: page.rows[0].id)
        do { let v = await first(e.policyGroups())![4].selected; XCTAssertEqual(v, page.rows[0].name) }
        do { _ = try await e.groupMembers(group: "x", offset: 0, limit: 1); XCTFail() } catch let err as ZephyrError { XCTAssertEqual(err.code, .groupNotFound) }
        let updates = e.latencyUpdates()
        try await e.testGroup(group: "故障转移")
        var it = updates.makeAsyncIterator()
        do { let v = await it.next()?.count; XCTAssertEqual(v, 100) }
    }

    func testCommands() async {
        let e = MockEngine(clock: .frozen941)
        let empty = await e.commandSuggestions(input: "")
        XCTAssertTrue((1...8).contains(empty.count))
        do { let v = await e.commandSuggestions(input: "github.com").first?.kind; XCTAssertEqual(v, .testRule) }
        do { let v = await e.commandSuggestions(input: "8.8.8.8").first?.kind; XCTAssertEqual(v, .testRule) }
        let tokyo = await e.commandSuggestions(input: "东京")
        XCTAssertEqual(tokyo.map(\.kind), [.openNodeQuery, .switchNode])
        XCTAssertEqual(tokyo[1].payload, String(MockFixtures.tk03.summary.id))
        let hkt = await e.commandSuggestions(input: "hkt")
        XCTAssertEqual(hkt.map(\.kind), [.openNodeQuery, .switchNode])
        let g = await e.commandSuggestions(input: "全局")
        XCTAssertEqual(g.first?.kind, .switchMode); XCTAssertEqual(g.first?.payload, "global")
        do { let v = await e.commandSuggestions(input: "设置").first?.payload; XCTAssertEqual(v, "settings") }
        do { let v = await e.commandSuggestions(input: "qwertyuiop").isEmpty; XCTAssertTrue(v) }
    }

    func testLogsAndConnections() async throws {
        let e = MockEngine(clock: .frozen941)
        var lines: [LogLine] = []
        for await l in e.logs(minLevel: .warning) { lines.append(l); break }
        XCTAssertEqual(lines.first?.level, .warning)
        let conns = await first(e.activeConnections())!
        XCTAssertEqual(conns.count, MockFixtures.connectionSeeds.count)
        XCTAssertTrue(conns.allSatisfy { $0.startedAt >= e.clock.now() - MockClock.prototypeConnectedMillis })
        try await e.closeConnection(id: conns[0].id)
        do { let v = await first(e.activeConnections())!.count; XCTAssertEqual(v, conns.count - 1) }
        try await e.closeAll()
        do { let v = await first(e.activeConnections())!.isEmpty; XCTAssertTrue(v) }
    }

    func testThreadSafety() async throws {
        let e = MockEngine(clock: .frozen941)
        try await withThrowingTaskGroup(of: Void.self) { g in
            for i in 0..<200 {
                g.addTask {
                    let r = try await e.queryNodes(query: ["jp", "iplc", "东京 ntt", "hk", ""][i % 5])
                    _ = try await e.nodeRows(token: r.token, offset: Int64(i * 37), limit: 50)
                    await e.testLatency(ids: [MockNodes.id(i % 15, Int64(i))])
                    try await e.applySceneChange(sceneId: "ai", nodeId: MockFixtures.aiPool[i % 9].summary.id)
                }
            }
            try await g.waitForAll()
        }
        do { let v = await e.nodeIndex().testedCount; XCTAssertEqual(v, 41_280 + 200) }
    }
}

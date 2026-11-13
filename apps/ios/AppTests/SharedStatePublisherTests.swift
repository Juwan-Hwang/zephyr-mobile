// SharedStatePublisher（REVIEW-Q2 X-P1-8）：契约类型 → SharedState 的映射、"显著变化"判定、写盘节流、
// 与扩展写入的速率按时间戳合并。每个用例用独立临时目录的 SharedStore（notify: false），不碰 App Group。
// 只调用 apply(...)，不 start()，因此引擎流不参与；MockEngine 仅用于满足初始化。

import XCTest
import ZephyrKit
import ZephyrMock

@MainActor
final class SharedStatePublisherTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!
    private var publisher: SharedStatePublisher!
    private var changes: [(SharedState, Bool)] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublisherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SharedStore(directory: directory, notify: false)
        publisher = SharedStatePublisher(engine: MockEngine(seed: 1), store: store)
        changes = []
        publisher.onChange = { [weak self] state, significant in self?.changes.append((state, significant)) }
    }

    override func tearDown() async throws {
        publisher.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func nowMillis(_ offset: TimeInterval = 0) -> Int64 { Int64((Date().timeIntervalSince1970 + offset) * 1000) }

    private func scene(_ id: String, node: String, latency: Int32?) -> Scene {
        Scene(id: id, kind: .ai, name: id.uppercased(), available: 3,
              selected: NodeSummary(id: 1, name: node, region: "JP", protocol: "vless", latencyMs: latency),
              source: .auto)
    }

    // MARK: 显著变化

    func testConnectionStatusOrModeChangeIsSignificant() {
        publisher.apply(connection: ConnectionState(status: .connected, mode: .rule, since: nowMillis()))
        XCTAssertEqual(changes.last?.1, true)
        publisher.apply(connection: ConnectionState(status: .connected, mode: .rule, since: nowMillis()))
        XCTAssertEqual(changes.last?.1, false, "状态与模式都没变")
        publisher.apply(connection: ConnectionState(status: .connected, mode: .global, since: nowMillis()))
        XCTAssertEqual(changes.last?.1, true, "模式变化")
        XCTAssertEqual(publisher.state.tunnel.mode, .global)
    }

    func testTrafficIsNeverSignificant() {
        publisher.apply(traffic: TrafficSample(at: nowMillis(), upBps: 10, downBps: 2_000))
        XCTAssertEqual(changes.last?.1, false)
        XCTAssertEqual(publisher.state.rate.downBps, 2_000)
        XCTAssertEqual(publisher.state.rate.recentDown.last, 2_000)
    }

    func testSceneLatencyValueChangeIsNotSignificantButNodeChangeIs() {
        publisher.apply(scenes: [scene("ai", node: "东京 01", latency: 40)])
        XCTAssertEqual(changes.last?.1, true, "首个场景列表")
        publisher.apply(scenes: [scene("ai", node: "东京 01", latency: 55)])
        XCTAssertEqual(changes.last?.1, false, "仅延迟数值变化（X-P1-15）")
        publisher.apply(scenes: [scene("ai", node: "东京 01", latency: -1)])
        XCTAssertEqual(changes.last?.1, true, "延迟档位变为超时")
        publisher.apply(scenes: [scene("ai", node: "大阪 02", latency: -1)])
        XCTAssertEqual(changes.last?.1, true, "出口节点变化")
    }

    func testScenesAreCappedAtFour() {
        publisher.apply(scenes: (0..<6).map { scene("s\($0)", node: "n\($0)", latency: 30) })
        XCTAssertEqual(publisher.state.scenes.map(\.id), ["s0", "s1", "s2", "s3"])
        XCTAssertEqual(publisher.state.scenes.first?.latencyMs, 30)
    }

    // MARK: 断开归零

    func testDisconnectZeroesRateWithFreshTimestamp() {
        publisher.apply(traffic: TrafficSample(at: nowMillis(-1), upBps: 5, downBps: 900))
        let before = Date()
        publisher.apply(connection: ConnectionState(status: .disconnected, mode: .rule))
        XCTAssertEqual(publisher.state.rate.downBps, 0)
        XCTAssertEqual(publisher.state.rate.upBps, 0)
        XCTAssertGreaterThanOrEqual(publisher.state.rate.at ?? .distantPast, before.addingTimeInterval(-0.01))
    }

    // MARK: 写盘节流与合并

    func testFirstCommitWritesImmediatelyAndSignificantBypassesThrottle() {
        publisher.apply(traffic: TrafficSample(at: nowMillis(), upBps: 1, downBps: 111))
        XCTAssertEqual(store.read().rate.downBps, 111, "首次（距上次写盘超过 5 s）立即写")

        publisher.apply(traffic: TrafficSample(at: nowMillis(), upBps: 1, downBps: 222))
        XCTAssertEqual(store.read().rate.downBps, 111, "5 s 内的速率只排队，不立即写")

        publisher.apply(connection: ConnectionState(status: .connected, mode: .global, since: nowMillis()))
        let disk = store.read()
        XCTAssertEqual(disk.connection.mode, .global, "显著变化立即写")
        XCTAssertEqual(disk.rate.downBps, 222, "排队中的速率随显著写一并落盘")
    }

    func testOnlyDirtyFieldsAreMergedIntoDisk() throws {
        // 扩展先写了 bypassLAN 之外的字段：App 只合并自己改过的字段，未改的保持盘上值。
        _ = try store.update { $0.accent = "pink" }
        publisher.apply(connection: ConnectionState(status: .connected, mode: .rule, since: nowMillis()))
        XCTAssertEqual(store.read().accent, "pink", "外观字段未脏，不得被 App 内存里的旧值覆盖")
        XCTAssertEqual(store.read().connection.status, .connected)
    }

    func testNewerRateOnDiskWinsAndIsAdoptedInMemory() throws {
        let future = Date().addingTimeInterval(60)
        _ = try store.update { s in
            s.rate.push(down: 7_777, up: 7, at: future)
        }
        publisher.apply(connection: ConnectionState(status: .connected, mode: .global, since: nowMillis()))
        publisher.apply(traffic: TrafficSample(at: nowMillis(), upBps: 1, downBps: 1))
        publisher.apply(connection: ConnectionState(status: .connected, mode: .rule, since: nowMillis()))
        XCTAssertEqual(store.read().rate.downBps, 7_777, "盘上（扩展写的）速率更新，App 的旧速率不覆盖")
        XCTAssertEqual(publisher.state.rate.downBps, 7_777, "内存跟上盘上的新速率")
        XCTAssertEqual(changes.last?.0.rate.downBps, 7_777, "onChange 推送合并后的速率")
    }

    func testUsageMapping() {
        publisher.apply(usage: UsageSummary(todayBytes: 4_096, regionsToday: 3, onlineMillisToday: 0,
                                            fastestLatencyMs: 38, hourly: Array(repeating: 1, count: 24)))
        XCTAssertEqual(publisher.state.usage.todayBytes, 4_096)
        XCTAssertEqual(publisher.state.usage.regionsToday, 3)
        XCTAssertEqual(publisher.state.usage.fastestLatencyMs, 38)
        XCTAssertEqual(changes.last?.1, false)
    }

    func testDateFromMillis() {
        XCTAssertEqual(SharedStatePublisher.date(fromMillis: 1_500).timeIntervalSince1970, 1.5, accuracy: 1e-9)
    }
}

// MockEngine —— ZephyrEngine 的确定性实现（contract/mock-spec.md）。同种子同时钟 → 同结果。
// 线程安全：全部可变状态在一把锁后面；流用 Broadcaster 分发。任意线程可调用。
// seed 只影响流量抖动与订阅 diff；节点库 / 规则 / 场景与种子无关（必须与 fixtures 一致）。

import Foundation
import ZephyrKit

public final class MockEngine: ZephyrEngine, @unchecked Sendable {

    public let seed: UInt64
    public let clock: MockClock

    struct State {
        var connection: ConnectionState
        var globalNode: NodeSummary
        var scenes: [Scene]
        var groups: [PolicyGroup]
        var subscriptions: [Subscription]
        var settings: Settings
        var tested: [NodeId: Int32] = [:]
        var testedCount: Int64 = 0
        var models: [Int64: MockQueryModel] = [:]
        var modelOrder: [Int64] = []
        var nextToken: Int64 = 1
        var closedConnections: Set<String> = []
        var logBacklog: [LogLine] = []
        var importCount = 0
    }

    let lock = NSLock()
    var state: State
    var ticker: Task<Void, Never>?

    let connectionB = Broadcaster<ConnectionState>()
    let trafficB = Broadcaster<TrafficSample>()
    let scenesB = Broadcaster<[Scene]>()
    let groupsB = Broadcaster<[PolicyGroup]>()
    let latencyB = Broadcaster<[LatencyUpdate]>()
    let subsB = Broadcaster<[Subscription]>()
    let connsB = Broadcaster<[ConnectionInfo]>()
    let logsB = Broadcaster<LogLine>()
    let settingsB = Broadcaster<Settings>()

    static let fullModel = MockQuery.build("")
    static let maxModels = 128

    /// - Parameters:
    ///   - seed: 流量抖动与订阅 diff 的种子。
    ///   - clock: `.live` 或 `.frozen941`（原型 9:41，快照用）。
    ///   - startConnected: nil = 冻结时钟下已连接（时长 2:14:07），实时时钟下未连接。
    public init(seed: UInt64 = 0, clock: MockClock = .live, startConnected: Bool? = nil) {
        self.seed = seed
        self.clock = clock
        let now = clock.now()
        let connected = startConnected ?? clock.isFrozen
        let conn = ConnectionState(status: connected ? .connected : .disconnected, mode: .rule,
                                   since: connected ? now - MockClock.prototypeConnectedMillis : nil,
                                   globalNodeId: nil,
                                   network: NetworkInfo(kind: .wifi, name: "Studio 5G", trusted: false), error: nil)
        let groups = MockFixtures.groups.map { g -> PolicyGroup in
            let m = MockQuery.build(g.2)
            let first = m.node(ordinal: 0).map { MockNodes.nodeName($0.r, $0.j) }
            return PolicyGroup(name: g.0, type: g.1, selected: first, memberCount: Int32(min(g.3, m.total)), testedAt: now - 2 * 3_600_000)
        }
        state = State(connection: conn, globalNode: MockFixtures.tk03.summary, scenes: MockFixtures.initialScenes(now: now),
                      groups: groups, subscriptions: MockFixtures.initialSubscriptions(now: now), settings: MockFixtures.settings)
        state.models[0] = Self.fullModel
        var t = now - Int64(MockFixtures.initialLogs.count) * 1000
        state.logBacklog = MockFixtures.initialLogs.map { l in t += 1000; return LogLine(at: t, level: l.0, message: l.1) }
        if connected { startTicker() }
    }

    deinit { ticker?.cancel() }

    // MARK: 内部工具

    @inline(__always) func withState<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(&state)
    }

    func log(_ level: LogLevel, _ message: String) {
        let line = LogLine(at: clock.now(), level: level, message: message)
        withState { s in
            s.logBacklog.append(line)
            if s.logBacklog.count > 500 { s.logBacklog.removeFirst(s.logBacklog.count - 500) }
        }
        logsB.send(line)
    }

    /// 生成节点或具名节点 → NodeSummary（带最新延迟）。
    func resolve(_ id: NodeId) -> NodeSummary? {
        if let p = MockFixtures.pinnedById[id] { return p.summary }
        guard let (r, j) = MockNodes.split(id) else { return nil }
        let lat = withState { $0.tested[id] } ?? MockNodes.cachedLatency(r, j)
        return MockNodes.summary(r, j, latency: lat)
    }

    func emitConnection() { connectionB.send(withState { $0.connection }) }
    func emitScenes() { scenesB.send(withState { $0.scenes }) }

    // MARK: §1 连接与模式

    public func connectionState() -> AsyncStream<ConnectionState> {
        lock.lock(); defer { lock.unlock() }
        return connectionB.stream(initial: [state.connection])
    }

    public func connect() async throws {
        let proceed = withState { s -> Bool in
            guard s.connection.status == .disconnected || s.connection.status == .failed else { return false }
            s.connection.status = .connecting; s.connection.error = nil
            return true
        }
        guard proceed else { return }
        emitConnection()
        log(.info, "正在连接…")
        await clock.sleep(ms: 600)
        if Task.isCancelled {
            withState { $0.connection.status = .disconnected }
            emitConnection()
            throw ZephyrError(code: .cancelled, message: "connect cancelled")
        }
        let now = clock.now()
        withState { s in
            s.connection.status = .connected
            s.connection.since = now
            s.closedConnections = []
        }
        emitConnection()
        log(.info, "已连接 · 规则模式")
        startTicker()
        trafficB.send(sample(at: now))
        connsB.send(currentConnections())
    }

    public func disconnect() async throws {
        let proceed = withState { s -> Bool in
            guard s.connection.status == .connected || s.connection.status == .connecting else { return false }
            s.connection.status = .disconnecting
            return true
        }
        guard proceed else { return }
        emitConnection()
        stopTicker()
        await clock.sleep(ms: 200)
        withState { s in s.connection.status = .disconnected; s.connection.since = nil }
        emitConnection()
        connsB.send([])
        log(.info, "已断开")
    }

    public func setMode(mode: ProxyMode) async throws {
        withState { s in
            s.connection.mode = mode
            s.connection.globalNodeId = mode == .global ? s.globalNode.id : nil
        }
        emitConnection()
        log(.info, "模式：\(["rule": "规则", "global": "全局", "direct": "直连"][mode.rawValue]!)")
    }

    public func setGlobalNode(id: NodeId) async throws -> ExitChange {
        guard let node = resolve(id) else { throw ZephyrError(code: .nodeNotFound, message: "node \(id)") }
        let change = withState { s -> ExitChange in
            let from = s.globalNode
            s.globalNode = node
            if s.connection.mode == .global { s.connection.globalNodeId = id }
            return ExitChange(sceneId: nil, fromRegion: from.region, fromIp: MockFixtures.exitIp(for: from.id),
                              toRegion: node.region, toIp: MockFixtures.exitIp(for: id), affectedApps: [], unchangedApps: [])
        }
        emitConnection()
        log(.info, "全局出口：\(node.name)")
        return change
    }

    // MARK: §2 流量与用量

    func sample(at ms: Int64) -> TrafficSample {
        if clock.fixedMillis == MockClock.prototypeMillis && seed == 0 && ms / 1000 == MockClock.prototypeMillis / 1000 {
            return MockFixtures.prototypeSample(at: (ms / 1000) * 1000)
        }
        return MockFixtures.traffic(second: ms / 1000, seed: seed)
    }

    public func traffic() -> AsyncStream<TrafficSample> {
        lock.lock(); defer { lock.unlock() }
        let initial = state.connection.status == .connected ? [sample(at: clock.now())] : []
        return trafficB.stream(initial: initial)
    }

    public func recentTraffic(seconds: Int32) -> [TrafficSample] {
        let (status, since) = withState { ($0.connection.status, $0.connection.since) }
        guard status == .connected, let since, seconds > 0 else { return [] }
        let nowS = clock.now() / 1000
        let n = Int64(min(seconds, 300))
        let start = max(nowS - n + 1, since / 1000)
        guard start <= nowS else { return [] }
        return (start...nowS).map { sample(at: $0 * 1000) }
    }

    public func usageToday() async -> UsageSummary { MockFixtures.usage() }

    func startTicker() {
        guard clock.realDelays else { return }
        lock.lock(); defer { lock.unlock() }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.withState({ $0.connection.status }) == .connected else { continue }
                self.trafficB.send(self.sample(at: self.clock.now()))
                self.connsB.send(self.currentConnections())
            }
        }
    }

    func stopTicker() {
        lock.lock(); defer { lock.unlock() }
        ticker?.cancel(); ticker = nil
    }
}

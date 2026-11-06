// MockEngine §6 规则 · §7 订阅 · §8 连接/日志/设置 · §9 命令搜索。

import Foundation
import ZephyrKit

extension MockEngine {

    // MARK: §6 规则

    public func ruleStats() async -> RuleStats {
        let now = clock.now()
        let ages: [Int64?] = [nil, 2, 3, 3, 1, 50, 50]
        let layers = MockRules.layers.enumerated().map { i, l in
            RuleLayer(index: Int32(i), kind: l.0, name: l.1, count: l.2, note: l.3, updatedAt: ages[i].map { now - $0 * 3_600_000 })
        }
        return RuleStats(total: MockRules.total, layers: layers, compiled: true, diskBytes: MockRules.diskBytes)
    }

    public func testRule(input: String) async throws -> RuleTrace {
        guard let m = MockRules.match(input) else { throw ZephyrError(code: .ruleInputInvalid, message: "empty input") }
        let took = 10 + Int64(m.q.count)
        let policy = MockRules.contractPolicy(m.hit?.policy ?? "O")
        let scene = withState { s in s.scenes.first { $0.id == policy } }
        return RuleTrace(input: m.q, isIp: m.isIp, layerIndex: m.hit.map { Int32($0.layer) }, rule: m.hit?.rule ?? "MATCH",
                         ruleNo: m.hit?.ruleNo, policy: policy, scene: scene, exitIp: scene?.exitIp, tookMicros: took)
    }

    // MARK: §7 订阅

    public func subscriptions() -> AsyncStream<[Subscription]> {
        lock.lock(); defer { lock.unlock() }
        return subsB.stream(initial: [state.subscriptions])
    }

    public func subscriptionsSummary() async -> SubscriptionsSummary {
        withState { s in SubscriptionsSummary(count: Int32(s.subscriptions.count), totalNodes: s.subscriptions.reduce(0) { $0 + $1.nodeCount }) }
    }

    public func importSubscription(source: ImportSource, payload: String) async throws -> Subscription {
        let p = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        var host = "本地配置"
        switch source {
        case .url, .clipboard, .qr:
            guard let u = URL(string: p), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let h = u.host, !h.isEmpty else {
                throw ZephyrError(code: .subscriptionInvalid, message: "not an http(s) url")
            }
            host = h
        case .file:
            guard p.contains("proxies:") || p.contains("proxy-providers:") else {
                throw ZephyrError(code: .subscriptionInvalid, message: "not a clash/mihomo config")
            }
        }
        await clock.sleep(ms: 800)
        let now = clock.now()
        let sub = withState { s -> Subscription in
            s.importCount += 1
            var acc: Int64 = 0
            for u in p.unicodeScalars { acc = (acc &* 31 &+ Int64(u.value)) & 0xFFFF_FFFF }
            let h = MockNodes.hsh(10, acc)
            let sub = Subscription(id: "import-\(s.importCount)", name: host, url: source == .file ? nil : "https://\(host)/••••••",
                                   nodeCount: Int64(1000 + h % 5000), usedBytes: 0, totalBytes: 100_000_000_000,
                                   remainingBytes: 100_000_000_000, expiresAt: now + 30 * 86_400_000, updatedAt: now,
                                   autoUpdateHours: s.settings.autoUpdateHours, lastDiff: nil)
            s.subscriptions.append(sub)
            return sub
        }
        subsB.send(withState { $0.subscriptions })
        log(.info, "已导入订阅 \(sub.name) · \(ZFormat.count(sub.nodeCount)) 个节点")
        return sub
    }

    func requireSub(_ id: String) throws {
        guard withState({ s in s.subscriptions.contains { $0.id == id } }) else {
            throw ZephyrError(code: .subscriptionInvalid, message: "no subscription \(id)")
        }
    }

    public func previewUpdate(id: String) async throws -> SubscriptionDiff {
        try requireSub(id)
        return MockFixtures.diff(for: id, seed: seed)
    }

    public func updateSubscription(id: String) async throws -> SubscriptionDiff {
        try requireSub(id)
        await clock.sleep(ms: 500)
        let d = MockFixtures.diff(for: id, seed: seed)
        let now = clock.now()
        withState { s in
            if let i = s.subscriptions.firstIndex(where: { $0.id == id }) { s.subscriptions[i].updatedAt = now; s.subscriptions[i].lastDiff = d }
        }
        subsB.send(withState { $0.subscriptions })
        log(.info, "订阅已更新 \(id)：+\(d.addedNodes) / −\(d.removedNodes)")
        return d
    }

    public func updateAll() async throws -> [SubscriptionDiff] {
        await clock.sleep(ms: 1200)
        let now = clock.now()
        let diffs = withState { s -> [SubscriptionDiff] in
            s.subscriptions.indices.map { i in
                let d = MockFixtures.diff(for: s.subscriptions[i].id, seed: seed)
                s.subscriptions[i].updatedAt = now; s.subscriptions[i].lastDiff = d
                return d
            }
        }
        subsB.send(withState { $0.subscriptions })
        log(.info, "已更新全部 \(diffs.count) 个订阅")
        return diffs
    }

    public func deleteSubscription(id: String) async throws {
        try requireSub(id)
        withState { s in s.subscriptions.removeAll { $0.id == id } }
        subsB.send(withState { $0.subscriptions })
        log(.info, "已删除订阅 \(id)")
    }

    // MARK: §8 连接、日志、设置

    func currentConnections() -> [ConnectionInfo] {
        let (status, since, closed, scenes) = withState { ($0.connection.status, $0.connection.since, $0.closedConnections, $0.scenes) }
        guard status == .connected, let since else { return [] }
        let now = clock.now()
        return MockFixtures.connectionSeeds.enumerated().compactMap { i, c in
            let id = "c\(i + 1)"
            if closed.contains(id) { return nil }
            let h = MockNodes.hsh(11, Int64(i))
            let started = max(since, now - Int64(h % 1800 + 5) * 1000)
            let secs = max(1, (now - started) / 1000)
            var node = "DIRECT"
            if let sid = c.2, let sc = scenes.first(where: { $0.id == sid }) {
                node = sc.exceptions.first { $0.app == c.1 }?.node.name ?? sc.selected.name
            }
            return ConnectionInfo(id: id, host: c.0, app: c.1, scene: c.2, node: node,
                                  upBytes: secs * Int64(500 + h % 4000), downBytes: secs * Int64(2000 + (h >> 7) % 90_000),
                                  startedAt: started)
        }
    }

    public func activeConnections() -> AsyncStream<[ConnectionInfo]> {
        connsB.stream(initial: [currentConnections()])
    }

    public func closeConnection(id: String) async throws {
        withState { _ = $0.closedConnections.insert(id) }
        connsB.send(currentConnections())
    }

    public func closeAll() async throws {
        withState { s in for i in MockFixtures.connectionSeeds.indices { s.closedConnections.insert("c\(i + 1)") } }
        connsB.send([])
        log(.info, "已关闭全部连接")
    }

    public func logs(minLevel: LogLevel) -> AsyncStream<LogLine> {
        lock.lock(); defer { lock.unlock() }
        return logsB.stream(initial: state.logBacklog, filter: { $0.level >= minLevel })
    }

    public func settings() -> AsyncStream<Settings> {
        lock.lock(); defer { lock.unlock() }
        return settingsB.stream(initial: [state.settings])
    }

    public func updateSettings(patch: Settings) async throws {
        guard (1...65535).contains(patch.localProxyPort), patch.latencyTtlHours > 0, patch.autoUpdateHours > 0 else {
            throw ZephyrError(code: .internal, message: "invalid settings value")
        }
        withState { $0.settings = patch }
        settingsB.send(patch)
    }

    public func storage() async -> StorageInfo { MockFixtures.storage }

    // MARK: §9 命令搜索

    public func commandSuggestions(input: String) async -> [CommandSuggestion] {
        await MockCommands.suggest(input: input, engine: self)
    }
}

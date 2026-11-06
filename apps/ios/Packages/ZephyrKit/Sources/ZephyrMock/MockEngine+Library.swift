// MockEngine §3 场景 · §4 策略组 · §5 节点库。

import Foundation
import ZephyrKit

extension MockEngine {

    // MARK: §3 场景

    public func scenes() -> AsyncStream<[Scene]> {
        lock.lock(); defer { lock.unlock() }
        return scenesB.stream(initial: [state.scenes])
    }

    static let videoPool: [NodeSummary] = {
        var out = MockFixtures.videoPinned.map(\.summary)
        let hk = MockNodes.regionIndex(code: "HK")!
        var j: Int64 = 0
        while out.count < 22 {
            if let lat = MockNodes.cachedLatency(hk, j) { out.append(MockNodes.summary(hk, j, latency: lat)) }
            j += 1
        }
        return out
    }()

    func pool(_ sceneId: String) -> [NodeSummary]? {
        switch sceneId {
        case "ai": return MockFixtures.aiPool.map(\.summary)
        case "video": return Self.videoPool
        case "other": return MockFixtures.otherPool.map(\.summary)
        default: return nil
        }
    }

    public func sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary] {
        guard withState({ s in s.scenes.contains { $0.id == sceneId } }), let pool = pool(sceneId) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        let tested = withState { $0.tested }
        let list = pool
            .filter { region == nil || $0.region == region!.uppercased() }
            .map { n -> NodeSummary in var n = n; if let t = tested[n.id] { n.latencyMs = t }; return n }
        func key(_ l: Int32?) -> Int32 { guard let l, l >= 0 else { return .max } ; return l }
        return Array(list.enumerated().sorted { (key($0.element.latencyMs), $0.offset) < (key($1.element.latencyMs), $1.offset) }
            .map(\.element).prefix(50))
    }

    public func previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ExitChange {
        guard let scene = withState({ s in s.scenes.first { $0.id == sceneId } }) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        guard let node = resolve(nodeId) else { throw ZephyrError(code: .nodeNotFound, message: "node \(nodeId)") }
        let exceptionApps = scene.exceptions.map(\.app)
        let apps = MockFixtures.sceneApps[sceneId] ?? []
        return ExitChange(sceneId: sceneId, fromRegion: scene.selected.region, fromIp: scene.exitIp,
                          toRegion: node.region, toIp: MockFixtures.exitIp(for: nodeId),
                          affectedApps: apps.filter { !exceptionApps.contains($0) }, unchangedApps: exceptionApps)
    }

    public func applySceneChange(sceneId: String, nodeId: NodeId) async throws {
        guard let node = resolve(nodeId) else { throw ZephyrError(code: .nodeNotFound, message: "node \(nodeId)") }
        let ok = withState { s -> Bool in
            guard let i = s.scenes.firstIndex(where: { $0.id == sceneId }) else { return false }
            s.scenes[i].selected = node
            s.scenes[i].exitIp = MockFixtures.exitIp(for: nodeId)
            if s.scenes[i].source != .subscriptionGroup { s.scenes[i].source = .manual }
            return true
        }
        guard ok else { throw ZephyrError(code: .sceneNotFound, message: sceneId) }
        emitScenes()
        log(.info, "场景 \(sceneId) 出口：\(node.name)")
    }

    public func retestScene(sceneId: String) async throws -> Scene {
        guard withState({ s in s.scenes.contains { $0.id == sceneId } }) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        await clock.sleep(ms: 300)
        let now = clock.now()
        let scene = withState { s -> Scene in
            let i = s.scenes.firstIndex { $0.id == sceneId }!
            s.scenes[i].testedAt = now
            return s.scenes[i]
        }
        emitScenes()
        return scene
    }

    // MARK: §4 策略组

    public func policyGroups() -> AsyncStream<[PolicyGroup]> {
        lock.lock(); defer { lock.unlock() }
        return groupsB.stream(initial: [state.groups])
    }

    func groupModel(_ name: String) throws -> (MockQueryModel, Int64) {
        guard let g = MockFixtures.groups.first(where: { $0.0 == name }),
              let count = withState({ s in s.groups.first { $0.name == name }?.memberCount }) else {
            throw ZephyrError(code: .groupNotFound, message: name)
        }
        return (g.2.isEmpty ? Self.fullModel : MockQuery.build(g.2), Int64(count))
    }

    public func groupMembers(group: String, offset: Int32, limit: Int32) async throws -> NodePage {
        let (m, count) = try groupModel(group)
        let off = Int64(max(0, offset))
        let lim = Int64(min(max(0, limit), 500))
        let end = min(count, off + lim)
        let tested = withState { $0.tested }
        var rows: [NodeSummary] = []
        if off < end {
            rows.reserveCapacity(Int(end - off))
            for o in off..<end {
                guard let (r, j) = m.node(ordinal: o) else { break }
                let id = MockNodes.id(r, j)
                rows.append(MockNodes.summary(r, j, latency: tested[id] ?? MockNodes.cachedLatency(r, j)))
            }
        }
        return NodePage(rows: rows, offset: off, total: count)
    }

    public func selectInGroup(group: String, nodeId: NodeId) async throws {
        _ = try groupModel(group)
        guard let node = resolve(nodeId) else { throw ZephyrError(code: .nodeNotFound, message: "node \(nodeId)") }
        withState { s in
            if let i = s.groups.firstIndex(where: { $0.name == group }) { s.groups[i].selected = node.name }
        }
        groupsB.send(withState { $0.groups })
    }

    public func testGroup(group: String) async throws {
        let (m, count) = try groupModel(group)
        let ids = (0..<min(count, 100)).compactMap { m.node(ordinal: $0) }.map { MockNodes.id($0.r, $0.j) }
        let now = clock.now()
        withState { s in
            if let i = s.groups.firstIndex(where: { $0.name == group }) { s.groups[i].testedAt = now }
        }
        groupsB.send(withState { $0.groups })
        await testLatency(ids: ids)
    }

    // MARK: §5 节点库

    public func nodeIndex() async -> NodeIndex {
        let tested = withState { $0.testedCount }
        return NodeIndex(total: MockNodes.total, sections: Self.fullModel.sections, testedCount: MockNodes.testedBase + tested)
    }

    public func queryNodes(query: String) async throws -> NodeQueryResult {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmed.isEmpty ? Self.fullModel : MockQuery.build(query)
        let took = Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1000)
        let token: Int64 = trimmed.isEmpty ? 0 : withState { s in
            let t = s.nextToken
            s.nextToken += 1
            s.models[t] = model
            s.modelOrder.append(t)
            if s.modelOrder.count > Self.maxModels { s.models[s.modelOrder.removeFirst()] = nil }
            return t
        }
        return NodeQueryResult(query: query, total: model.total, sections: model.sections, highlights: model.highlights,
                               tookMicros: took, token: token)
    }

    public func nodeRows(token: Int64, offset: Int64, limit: Int32) async throws -> NodePage {
        guard let m = withState({ $0.models[token] }) else {
            throw ZephyrError(code: .internal, message: "unknown or expired query token \(token)")
        }
        return rows(model: m, offset: offset, limit: limit)
    }

    /// 同步分页（测试 / 预览用）。
    func rows(model m: MockQueryModel, offset: Int64, limit: Int32) -> NodePage {
        let off = max(0, offset)
        let lim = Int64(min(max(0, limit), 500))
        guard lim > 0, off < m.total, var (gi, k) = m.locate(ordinal: off) else {
            return NodePage(rows: [], offset: off, total: m.total)
        }
        let tested = withState { $0.tested }
        var rows: [NodeSummary] = []
        rows.reserveCapacity(Int(min(lim, m.total - off)))
        while Int64(rows.count) < lim && gi < m.groups.count {
            let g = m.groups[gi]
            if k >= g.count { gi += 1; k = 0; continue }
            let j = g.index(at: k)
            let id = MockNodes.id(g.region, j)
            rows.append(MockNodes.summary(g.region, j, latency: tested.isEmpty ? MockNodes.cachedLatency(g.region, j)
                                          : (tested[id] ?? MockNodes.cachedLatency(g.region, j))))
            k += 1
        }
        return NodePage(rows: rows, offset: off, total: m.total)
    }

    public func node(id: NodeId) async throws -> NodeDetail {
        guard let s = resolve(id) else { throw ZephyrError(code: .nodeNotFound, message: "node \(id)") }
        let h = MockNodes.hsh(9, Int64(id % 4_000_000_000))
        let ports: [Int32] = [443, 8443, 2053, 2083, 2096]
        let transports = ["tcp", "ws", "grpc", "h2", "quic"]
        let sub = h % 10 < 6 ? "Nebula Cloud" : h % 10 < 8 ? "Orbit" : "订阅 \(String(format: "%03d", Int(h % 212) + 3))"
        let hex = String(h % 0xFFFF, radix: 16)
        return NodeDetail(summary: s, server: "\(s.region.lowercased())-\(hex)•••.example.net", port: ports[Int(h % 5)],
                          subscription: sub,
                          extra: ["传输": transports[Int((h >> 4) % 5)], "TLS": h % 3 == 0 ? "Reality" : "TLS 1.3",
                                  "UDP": h % 4 == 0 ? "不支持" : "支持"])
    }

    public func testLatency(ids: [NodeId]) async {
        let now = clock.now()
        var plan: [(delay: Int64, update: LatencyUpdate)] = []
        for id in ids.prefix(100) {
            if let p = MockFixtures.pinnedById[id] {
                plan.append((80, LatencyUpdate(id: id, latencyMs: p.summary.latencyMs ?? -1, at: now)))
            } else if let (r, j) = MockNodes.split(id) {
                let delay = 80 + Int64(MockNodes.hsh(j, Int64(r)) % 321)
                plan.append((delay, LatencyUpdate(id: id, latencyMs: MockNodes.measuredLatency(r, j), at: now + delay)))
            }
        }
        guard !plan.isEmpty else { return }
        if !clock.realDelays {
            record(plan.map(\.update))
            latencyB.send(plan.map(\.update))
            return
        }
        plan.sort { $0.delay < $1.delay }
        Task { [weak self] in
            var elapsed: Int64 = 0
            var i = 0
            while i < plan.count {
                let bucket = plan[i].delay / 50
                var batch: [LatencyUpdate] = []
                while i < plan.count && plan[i].delay / 50 == bucket { batch.append(plan[i].update); i += 1 }
                let target = (bucket + 1) * 50
                if target > elapsed { try? await Task.sleep(nanoseconds: UInt64(target - elapsed) * 1_000_000); elapsed = target }
                guard let self else { return }
                let at = self.clock.now()
                let stamped = batch.map { LatencyUpdate(id: $0.id, latencyMs: $0.latencyMs, at: at) }
                self.record(stamped)
                self.latencyB.send(stamped)
            }
        }
    }

    func record(_ updates: [LatencyUpdate]) {
        withState { s in
            for u in updates {
                if MockFixtures.pinnedById[u.id] != nil { continue }
                if s.tested.updateValue(u.latencyMs, forKey: u.id) == nil { s.testedCount += 1 }
            }
        }
    }

    public func latencyUpdates() -> AsyncStream<[LatencyUpdate]> { latencyB.stream() }
}

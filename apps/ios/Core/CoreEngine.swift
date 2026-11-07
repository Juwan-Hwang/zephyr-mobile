// CoreEngine —— ZephyrEngine 的真实实现：节点库、规则、订阅、场景、存储走 Rust core-mobile（UniFFI，MobileCore）。
//
// 与 Android CoreEngine（apps/android/core-engine/.../CoreEngine.kt）同构：
//  - 核心有数据时走 MobileCore；没有数据或核心加载失败时，按 `mockData` 回落 MockEngine（Debug/演示）或给空状态（Release）。
//  - 平台只负责 HTTP 拉取订阅正文（URLSession），解析、清洗、存储、建库都在核心里。
//  - 连接、流量、策略组、连接列表等实时数据属于 PacketTunnel 里的 mihomo：有 `TunnelPort`（真机）时经它与
//    MihomoClient 读取（CoreEngine+Live.swift），否则转发 fallback（模拟器、单测）。
//  - UniFFI 调用是阻塞 FFI：一律放到 `work` 串行队列以外的并发队列执行，主线程不碰。
//
// 命名：本模块里不带前缀的 Scene/Subscription/NodePage… 是 UniFFI 生成的核心类型（本模块声明优先于导入）；
//       ZephyrKit 的同名领域类型一律写全 `ZephyrKit.X`。

import Foundation
import ZephyrKit
import ZephyrMock

public final class CoreEngine: ZephyrEngine, @unchecked Sendable {

    private let core: MobileCore?
    private let fallback: any ZephyrEngine
    private let mockData: Bool
    private let clock: @Sendable () -> Int64
    private let fetcher: @Sendable (URL) async throws -> FetchedBody
    private let queue = DispatchQueue(label: "app.zephyr.core", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()

    // 受 lock 保护
    private var nodesReady: Bool?
    private var rulesReady: Bool?
    private var queries: [UInt64: String] = [:]
    private var remapped: [UInt64: UInt64] = [:]
    private var subsWatchers: [UUID: AsyncStream<[ZephyrKit.Subscription]>.Continuation] = [:]
    private var sceneWatchers: [UUID: AsyncStream<[ZephyrKit.Scene]>.Continuation] = [:]
    private var latencyWatchers: [UUID: AsyncStream<[LatencyUpdate]>.Continuation] = [:]
    private var samples: [TrafficSample] = []
    private var members: [NodeId: String] = [:]

    /// 真机的系统隧道；nil = 模拟器 / 单测，实时数据走 fallback。
    let tunnel: (any TunnelPort)?

    /// 核心是否已加载（不代表已有数据）。
    public var isNative: Bool { core != nil }

    public struct FetchedBody: Sendable {
        public var body: String
        public var userInfo: String?
        public var fileName: String?
        public init(body: String, userInfo: String? = nil, fileName: String? = nil) {
            self.body = body; self.userInfo = userInfo; self.fileName = fileName
        }
    }

    /// - Parameters:
    ///   - dataDir: 核心数据目录（nodes.*.zn、rules/、subs/ …）。nil = 默认 Application Support/zephyr-core。
    ///   - mockData: 核心为空时是否用 MockEngine 的确定性数据顶上（Debug/演示 true，Release false）。
    public init(dataDir: URL? = nil,
                fallback: (any ZephyrEngine)? = nil,
                mockData: Bool = false,
                clock: @escaping @Sendable () -> Int64 = { ZFormat.nowMillis() },
                fetcher: (@Sendable (URL) async throws -> FetchedBody)? = nil,
                tunnel: (any TunnelPort)? = nil) {
        let dir = dataDir ?? CoreEngine.defaultDataDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.core = try? MobileCore(dataDir: dir.path)
        self.fallback = fallback ?? MockEngine(clock: .live)
        self.mockData = mockData
        self.clock = clock
        self.fetcher = fetcher ?? CoreEngine.httpFetch
        self.tunnel = tunnel
    }

    func now() -> Int64 { clock() }

    /// 最近 300 s 的流量样本（recentTraffic 用）。
    func remember(_ s: TrafficSample) {
        locked {
            samples.append(s)
            if samples.count > 300 { samples.removeFirst(samples.count - 300) }
        }
    }

    func rememberMembers(_ pairs: [(NodeId, String)]) {
        locked { for (id, name) in pairs { members[id] = name } }
    }

    func memberName(_ id: NodeId) -> String? { locked { members[id] } }

    public static func defaultDataDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("zephyr-core", isDirectory: true)
    }

    // MARK: - 基础设施

    /// 在后台队列执行阻塞 FFI，并把 MobileError 映射为 ZephyrError。
    private func run<T: Sendable>(_ notFound: ErrorCode = .nodeNotFound, _ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<T, Error>) in
            queue.async {
                do { k.resume(returning: try body()) } catch let e as MobileError {
                    k.resume(throwing: CoreEngine.map(e, notFound: notFound))
                } catch {
                    k.resume(throwing: error)
                }
            }
        }
    }

    private func runQuiet<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (k: CheckedContinuation<T, Never>) in queue.async { k.resume(returning: body()) } }
    }

    static func map(_ e: MobileError, notFound: ErrorCode = .nodeNotFound) -> ZephyrError {
        let message = "\(e)"
        switch e {
        case .NotFound: return ZephyrError(code: notFound, message: message)
        case .SceneNotFound: return ZephyrError(code: .sceneNotFound, message: message)
        case .Invalid, .RuleInputInvalid: return ZephyrError(code: .ruleInputInvalid, message: message)
        case .SubscriptionInvalid, .SubscriptionNotFound: return ZephyrError(code: .subscriptionInvalid, message: message)
        case .NotRunning: return ZephyrError(code: .notRunning, message: message)
        case .Cancelled: return ZephyrError(code: .cancelled, message: message)
        default: return ZephyrError(code: .internal, message: message)
        }
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private func invalidateNodes() { locked { nodesReady = nil } }

    /// 有节点数据时返回核心，否则 nil（调用方回落）。
    private func nodes() async -> MobileCore? {
        guard let c = core else { return nil }
        if let ready = locked({ nodesReady }) { return ready ? c : nil }
        let ok = await runQuiet { ((try? c.nodeIndex())?.total ?? 0) > 0 }
        locked { nodesReady = ok }
        return ok ? c : nil
    }

    private func rules() async -> MobileCore? {
        guard let c = core else { return nil }
        if let ready = locked({ rulesReady }) { return ready ? c : nil }
        let ok = await runQuiet { c.ruleStats().total > 0 }
        locked { rulesReady = ok }
        return ok ? c : nil
    }

    // MARK: - §1 连接与模式（VPN 生命周期属 PacketTunnel；此处转发）

    public func connectionState() -> AsyncStream<ConnectionState> {
        if let t = tunnel { return t.states() }
        return fallback.connectionState()
    }
    public func connect() async throws {
        if let t = tunnel { return try await liveConnect(t) }
        try await fallback.connect()
    }
    public func disconnect() async throws {
        if let t = tunnel { return try await t.stop() }
        try await fallback.disconnect()
    }
    public func setMode(mode: ZephyrKit.ProxyMode) async throws {
        if let t = tunnel { return try await t.setMode(mode) }
        try await fallback.setMode(mode: mode)
    }
    public func setGlobalNode(id: NodeId) async throws -> ZephyrKit.ExitChange { try await fallback.setGlobalNode(id: id) }

    // MARK: - §2 流量与用量

    public func traffic() -> AsyncStream<TrafficSample> {
        if let t = tunnel { return liveTraffic(t) }
        return fallback.traffic()
    }
    public func recentTraffic(seconds: Int32) -> [TrafficSample] {
        guard tunnel != nil else { return fallback.recentTraffic(seconds: seconds) }
        let since = clock() - Int64(seconds) * 1000
        return locked { samples.filter { $0.at >= since } }
    }
    public func usageToday() async -> UsageSummary { await fallback.usageToday() }

    // MARK: - §3 场景

    public func scenes() -> AsyncStream<[ZephyrKit.Scene]> {
        guard core != nil else { return mockData ? fallback.scenes() : CoreEngine.just([]) }
        let id = UUID()
        let (stream, cont) = AsyncStream<[ZephyrKit.Scene]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        locked { sceneWatchers[id] = cont }
        let task = Task { [weak self] in
            guard let self else { return }
            guard await self.nodes() != nil else {
                if self.mockData { for await v in self.fallback.scenes() { cont.yield(v) } } else { cont.yield([]) }
                return
            }
            var last: [ZephyrKit.Scene]?
            while !Task.isCancelled {
                if let v = try? await self.readScenes(), v != last { last = v; cont.yield(v) }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        cont.onTermination = { [weak self] _ in task.cancel(); self?.locked { _ = self?.sceneWatchers.removeValue(forKey: id) } }
        return stream
    }

    private func readScenes() async throws -> [ZephyrKit.Scene] {
        guard let c = core else { return [] }
        let now = clock()
        return try await run(.sceneNotFound) { try c.scenes(nowMillis: now) }.map(CoreEngine.scene)
    }

    private func bumpScenes() async {
        guard let v = try? await readScenes() else { return }
        for c in locked({ Array(sceneWatchers.values) }) { c.yield(v) }
    }

    public func sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary] {
        guard let c = await nodes() else { return mockData ? try await fallback.sceneCandidates(sceneId: sceneId, region: region) : [] }
        let now = clock()
        return try await run(.sceneNotFound) { try c.sceneCandidates(sceneId: sceneId, region: region, nowMillis: now) }
            .map { r in var s = CoreEngine.row(r.row); s.latencyMs = r.latencyMs > 0 ? r.latencyMs : nil; return s }
    }

    public func previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ZephyrKit.ExitChange {
        guard let c = await nodes() else { return try await fallback.previewSceneChange(sceneId: sceneId, nodeId: nodeId) }
        let x = try await run(.sceneNotFound) { try c.previewSceneChange(sceneId: sceneId, nodeId: nodeId) }
        return ZephyrKit.ExitChange(sceneId: x.sceneId, fromRegion: x.fromRegion ?? "", fromIp: x.fromIp, toRegion: x.toRegion,
                                    toIp: x.toIp, affectedApps: x.affectedApps, unchangedApps: x.unchangedApps)
    }

    public func applySceneChange(sceneId: String, nodeId: NodeId) async throws {
        guard let c = await nodes() else { return try await fallback.applySceneChange(sceneId: sceneId, nodeId: nodeId) }
        let now = clock()
        let apply = try await run(.sceneNotFound) { try c.applySceneChange(sceneId: sceneId, nodeId: nodeId, nowMillis: now) }
        await bumpScenes()
        // 隧道运行中：成员在组内 → 控制口热切换；否则重写配置并让扩展热重载（契约 §14.x）。
        if let t = tunnel {
            if apply.needsReload {
                await reloadTunnelIfRunning(t)
            } else {
                try? await mihomo(t.controllerSocketPath) { try $0.selectInGroup(group: apply.group, member: apply.member) }
            }
        }
    }

    /// 重测（契约 §14.z）：隧道在跑时经 VPN 真实探测——出口用 Cloudflare trace，服务用 probe 地址；
    /// 请求按域名走规则，测到的就是该场景（含应用例外）真正的出口。隧道没在跑时只返回缓存。
    public func retestScene(sceneId: String) async throws -> ZephyrKit.Scene {
        guard let c = await nodes() else { return try await fallback.retestScene(sceneId: sceneId) }
        if let t = tunnel, await isTunnelConnected(t) {
            let exitURL = try await run(.sceneNotFound) { try c.sceneExitProbe(sceneId: sceneId) }
            let targets = try await run(.sceneNotFound) { try c.sceneProbeTargets(sceneId: sceneId) }
            let session = CoreEngine.probeSession
            let now = clock
            await withTaskGroup(of: Void.self) { g in
                if let u = exitURL.flatMap(URL.init(string:)) {
                    g.addTask {
                        guard let (data, _) = try? await session.data(from: u) else { return }
                        _ = try? c.reportSceneTrace(sceneId: sceneId, body: String(decoding: data, as: UTF8.self), nowMillis: now())
                    }
                }
                for target in targets {
                    guard let u = URL(string: target.url) else { continue }
                    g.addTask {
                        var req = URLRequest(url: u)
                        req.httpMethod = "HEAD"
                        // 能拿到任何 HTTP 响应（含 403 地区限制页以外的）即视为可达；超时/连接失败为不可用。
                        let ok: Bool
                        if let (_, resp) = try? await session.data(for: req), let h = resp as? HTTPURLResponse {
                            ok = h.statusCode < 500 && h.statusCode != 403
                        } else {
                            ok = false
                        }
                        _ = try? c.reportSceneService(sceneId: sceneId, appId: target.appId, ok: ok, nowMillis: now())
                    }
                }
            }
        }
        guard let s = try await readScenes().first(where: { $0.id == sceneId }) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        await bumpScenes()
        return s
    }

    static let probeSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: cfg)
    }()

    public func setSceneSource(sceneId: String, source: ZephyrKit.SceneSource) async throws {
        guard let c = await nodes() else { return try await fallback.setSceneSource(sceneId: sceneId, source: source) }
        let src: SceneSource = switch source { case .auto: .auto; case .manual: .manual; case .subscriptionGroup: .subscriptionGroup }
        let now = clock()
        let apply = try await run(.sceneNotFound) { try c.setSceneSource(sceneId: sceneId, source: src, nowMillis: now) }
        await bumpScenes()
        if let apply, let t = tunnel {
            if apply.needsReload {
                await reloadTunnelIfRunning(t)
            } else {
                try? await mihomo(t.controllerSocketPath) { try $0.selectInGroup(group: apply.group, member: apply.member) }
            }
        }
    }

    public func overrideHost(host: String, target: ZephyrKit.TraceTarget, sceneId: String?, persistent: Bool) async throws {
        guard let c = core else { return try await fallback.overrideHost(host: host, target: target, sceneId: sceneId, persistent: persistent) }
        let tt: TraceTarget = switch target { case .unchanged: .unchanged; case .direct: .direct; case .scene: .scene }
        try await run(.ruleInputInvalid) { try c.overrideHost(host: host, target: tt, sceneId: sceneId, persistent: persistent) }
        await bumpScenes()
        if let t = tunnel { await reloadTunnelIfRunning(t) }
    }

    // MARK: - §4 策略组（mihomo 实时数据，在 PacketTunnel）

    public func policyGroups() -> AsyncStream<[ZephyrKit.PolicyGroup]> {
        if let t = tunnel { return livePolicyGroups(t) }
        return mockData ? fallback.policyGroups() : CoreEngine.just([])
    }
    public func groupMembers(group: String, offset: Int32, limit: Int32) async throws -> ZephyrKit.NodePage {
        if let t = tunnel { return try await liveGroupMembers(t, group: group, offset: offset, limit: limit) }
        return try await fallback.groupMembers(group: group, offset: offset, limit: limit)
    }
    public func selectInGroup(group: String, nodeId: NodeId) async throws {
        if let t = tunnel { return try await liveSelect(t, group: group, nodeId: nodeId) }
        try await fallback.selectInGroup(group: group, nodeId: nodeId)
    }
    public func testGroup(group: String) async throws {
        if let t = tunnel { return try await liveTestGroup(t, group: group) }
        try await fallback.testGroup(group: group)
    }

    // MARK: - §5 节点库

    public func nodeIndex() async -> ZephyrKit.NodeIndex {
        guard let c = await nodes() else {
            return mockData ? await fallback.nodeIndex() : ZephyrKit.NodeIndex(total: 0, sections: [], testedCount: 0)
        }
        guard let i = try? await run(.nodeNotFound, { try c.nodeIndex() }) else { return ZephyrKit.NodeIndex(total: 0, sections: [], testedCount: 0) }
        let tested = await runQuiet { c.testedCount(nowMillis: self.clock(), maxAgeMillis: CoreEngine.latencyFreshMillis) }
        return ZephyrKit.NodeIndex(total: Int64(i.total), sections: i.sections.map(CoreEngine.section), testedCount: Int64(tested))
    }

    public func queryNodes(query: String) async throws -> ZephyrKit.NodeQueryResult {
        guard let c = await nodes() else {
            if mockData { return try await fallback.queryNodes(query: query) }
            return ZephyrKit.NodeQueryResult(query: query, total: 0, sections: [], highlights: [], tookMicros: 0, token: 0)
        }
        let r = try await run { try c.queryNodes(query: query) }
        locked { queries[r.token] = query }
        return ZephyrKit.NodeQueryResult(query: r.query, total: Int64(r.total), sections: r.sections.map(CoreEngine.section),
                                         highlights: r.highlights, tookMicros: Int64(r.tookMicros), token: Int64(bitPattern: r.token))
    }

    public func nodeRows(token: Int64, offset: Int64, limit: Int32) async throws -> ZephyrKit.NodePage {
        guard let c = await nodes() else {
            if mockData { return try await fallback.nodeRows(token: token, offset: offset, limit: limit) }
            return ZephyrKit.NodePage(rows: [], offset: offset, total: 0)
        }
        let original = UInt64(bitPattern: token)
        let t = locked { remapped[original] ?? original }
        let off = UInt64(max(0, offset)), lim = UInt32(max(0, min(500, limit)))
        let page: NodePage
        do {
            page = try await withCheckedThrowingContinuation { (k: CheckedContinuation<NodePage, Error>) in
                queue.async { do { k.resume(returning: try c.nodeRows(token: t, offset: off, limit: lim)) } catch { k.resume(throwing: error) } }
            }
        } catch let e as MobileError {
            guard case .StaleToken = e else { throw CoreEngine.map(e) }
            // 订阅更新重建了库：用同一查询换新 token，列表继续翻页（与 Android 一致）。
            guard let q = locked({ queries[original] }) else { throw ZephyrError(code: .internal, message: "stale_token") }
            let fresh = try await run { try c.queryNodes(query: q) }.token
            locked { queries[fresh] = q; remapped[original] = fresh }
            page = try await run { try c.nodeRows(token: fresh, offset: off, limit: lim) }
        }
        let ids = page.rows.map(\.id)
        let now = clock()
        let lat = await runQuiet { c.cachedLatencies(ids: ids, nowMillis: now, maxAgeMillis: 30 * 60 * 1000) }
        let rows = zip(page.rows, lat).map { r, ms -> NodeSummary in var s = CoreEngine.row(r); s.latencyMs = ms; return s }
        return ZephyrKit.NodePage(rows: rows, offset: Int64(page.offset), total: Int64(page.total))
    }

    static let latencyFreshMillis: Int64 = 24 * 3_600_000

    public func node(id: NodeId) async throws -> ZephyrKit.NodeDetail {
        guard let c = await nodes() else {
            if mockData { return try await fallback.node(id: id) }
            throw ZephyrError(code: .nodeNotFound, message: String(id, radix: 16))
        }
        let d = try await run(.nodeNotFound) { try c.nodeDetail(id: id) }
        var summary = CoreEngine.row(d.row)
        if let ms = d.latencyMs { summary.latencyMs = ms }
        return ZephyrKit.NodeDetail(summary: summary, server: d.server, port: d.port, subscription: d.subscription, extra: d.extra)
    }

    /// 契约 §5：分批（≤512）由核心给出代理定义，扩展里 zm_url_test 实测，结果入核心延迟缓存并推给 latencyUpdates。
    /// 隧道未连接时不测（App 进程未链接 mihomo；未连接时的测速见 docs/perf.md 待办）。
    public func testLatency(ids: [NodeId]) async {
        guard let c = await nodes() else { return await fallback.testLatency(ids: ids) }
        guard let t = tunnel, await isTunnelConnected(t) else { return }
        var seen = Set<NodeId>()
        let unique = ids.filter { seen.insert($0).inserted }
        for start in stride(from: 0, to: unique.count, by: 512) {
            if Task.isCancelled { return }
            let chunk = Array(unique[start..<min(start + 512, unique.count)])
            guard let json = try? await run({ try c.latencyTestBatch(ids: chunk) }), json != "[]",
                  let out = await t.urlTest(proxiesJSON: json, url: "https://www.gstatic.com/generate_204", timeoutMs: 5000) else { continue }
            let now = clock()
            guard let samples = try? await run({ try c.recordUrlTest(resultJson: out, nowMillis: now) }), !samples.isEmpty else { continue }
            let updates = samples.map { LatencyUpdate(id: $0.id, latencyMs: $0.ms, at: $0.at) }
            for w in locked({ Array(latencyWatchers.values) }) { w.yield(updates) }
        }
    }

    public func latencyUpdates() -> AsyncStream<[LatencyUpdate]> {
        guard core != nil else { return fallback.latencyUpdates() }
        let id = UUID()
        let (stream, cont) = AsyncStream<[LatencyUpdate]>.makeStream(bufferingPolicy: .bufferingNewest(8))
        locked { latencyWatchers[id] = cont }
        cont.onTermination = { [weak self] _ in self?.locked { _ = self?.latencyWatchers.removeValue(forKey: id) } }
        return stream
    }

    // MARK: - §6 规则

    public func ruleStats() async -> ZephyrKit.RuleStats {
        guard let c = await rules() else {
            return mockData ? await fallback.ruleStats() : ZephyrKit.RuleStats(total: 0, layers: [], compiled: false, diskBytes: 0)
        }
        let s = await runQuiet { c.ruleStats() }
        return ZephyrKit.RuleStats(
            total: Int64(s.total),
            layers: s.layers.map { ZephyrKit.RuleLayer(index: Int32($0.index), kind: CoreEngine.kind($0.kind), name: $0.name,
                                                       count: Int64($0.count), note: $0.note) },
            compiled: true, diskBytes: Int64(s.diskBytes))
    }

    public func testRule(input: String) async throws -> ZephyrKit.RuleTrace {
        guard let c = await rules() else { return try await fallback.testRule(input: input) }
        let t = try await run(.ruleInputInvalid) { try c.testRule(input: input) }
        let scene = (try? await readScenes())?.first { $0.id == t.policy || $0.name.caseInsensitiveCompare(t.policy) == .orderedSame }
        return ZephyrKit.RuleTrace(input: t.input, isIp: t.isIp, layerIndex: t.layerIndex.map { Int32($0) }, rule: t.rule,
                                   ruleNo: t.ruleNo.map { Int64($0) }, policy: t.policy, scene: scene, exitIp: scene?.exitIp,
                                   tookMicros: Int64(t.tookMicros))
    }

    // MARK: - §7 订阅（核心解析/存储；平台只拉取）

    public func subscriptions() -> AsyncStream<[ZephyrKit.Subscription]> {
        guard core != nil else { return mockData ? fallback.subscriptions() : CoreEngine.just([]) }
        let id = UUID()
        let (stream, cont) = AsyncStream<[ZephyrKit.Subscription]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        locked { subsWatchers[id] = cont }
        cont.onTermination = { [weak self] _ in self?.locked { _ = self?.subsWatchers.removeValue(forKey: id) } }
        Task { [weak self] in await self?.publishSubs() }
        return stream
    }

    @discardableResult
    private func publishSubs() async -> [ZephyrKit.Subscription] {
        guard let c = core else { return [] }
        let list = await runQuiet { c.subscriptions() }.map(CoreEngine.sub)
        for w in locked({ Array(subsWatchers.values) }) { w.yield(list) }
        return list
    }

    public func subscriptionsSummary() async -> ZephyrKit.SubscriptionsSummary {
        guard let c = core else {
            return mockData ? await fallback.subscriptionsSummary() : ZephyrKit.SubscriptionsSummary(count: 0, totalNodes: 0)
        }
        let s = await runQuiet { c.subscriptionsSummary() }
        return ZephyrKit.SubscriptionsSummary(count: s.count, totalNodes: s.totalNodes)
    }

    public func importSubscription(source: ImportSource, payload: String) async throws -> ZephyrKit.Subscription {
        guard let c = core else { return try await fallback.importSubscription(source: source, payload: payload) }
        let p = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw ZephyrError(code: .subscriptionInvalid, message: "empty") }
        let url = CoreEngine.httpURL(p)
        if (source == .url || source == .qr) && url == nil { throw ZephyrError(code: .subscriptionInvalid, message: "not a subscription link") }
        let got: FetchedBody
        if let url { got = try await fetch(url) } else { got = FetchedBody(body: p) }
        let name = got.fileName.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty ? nil : $0 }
            ?? CoreEngine.defaultName(url)
        let fetched = FetchedSubscription(body: got.body, userinfo: got.userInfo, nowMillis: clock())
        let urlString = url?.absoluteString
        let s = try await run(.subscriptionInvalid) {
            try c.importSubscription(name: name, url: urlString, fetched: fetched, autoUpdateHours: 12, progress: nil)
        }
        invalidateNodes()
        await publishSubs()
        await bumpScenes()
        return CoreEngine.sub(s)
    }

    public func previewUpdate(id: String) async throws -> ZephyrKit.SubscriptionDiff {
        guard let c = core else { return try await fallback.previewUpdate(id: id) }
        let got = try await fetchFor(id, c)
        let fetched = FetchedSubscription(body: got.body, userinfo: got.userInfo, nowMillis: clock())
        return CoreEngine.diff(try await run(.subscriptionInvalid) { try c.previewSubscriptionUpdate(id: id, fetched: fetched) })
    }

    public func updateSubscription(id: String) async throws -> ZephyrKit.SubscriptionDiff {
        guard let c = core else { return try await fallback.updateSubscription(id: id) }
        let got = try await fetchFor(id, c)
        let fetched = FetchedSubscription(body: got.body, userinfo: got.userInfo, nowMillis: clock())
        let d = try await run(.subscriptionInvalid) { try c.updateSubscription(id: id, fetched: fetched, progress: nil) }
        invalidateNodes()
        await publishSubs()
        await bumpScenes()
        if let t = tunnel { await reloadTunnelIfRunning(t) }
        return CoreEngine.diff(d)
    }

    public func updateAll() async throws -> [ZephyrKit.SubscriptionDiff] {
        guard let c = core else { return try await fallback.updateAll() }
        let ids = await runQuiet { c.subscriptions() }.filter { $0.url != nil }.map(\.id)
        var out: [ZephyrKit.SubscriptionDiff] = []
        for id in ids { if let d = try? await updateSubscription(id: id) { out.append(d) } }
        return out
    }

    public func deleteSubscription(id: String) async throws {
        guard let c = core else { return try await fallback.deleteSubscription(id: id) }
        try await run(.subscriptionInvalid) { try c.deleteSubscription(id: id) }
        invalidateNodes()
        await publishSubs()
        await bumpScenes()
    }

    private func fetchFor(_ id: String, _ c: MobileCore) async throws -> FetchedBody {
        guard let raw = try await run(.subscriptionInvalid, { try c.subscriptionFetchUrl(id: id) }), let url = CoreEngine.httpURL(raw) else {
            throw ZephyrError(code: .subscriptionInvalid, message: "local profile")
        }
        return try await fetch(url)
    }

    private func fetch(_ url: URL) async throws -> FetchedBody {
        do { return try await fetcher(url) } catch let e as ZephyrError { throw e } catch {
            throw ZephyrError(code: .subscriptionFetchFailed, message: error.localizedDescription)
        }
    }

    /// 默认拉取：clash 兼容 UA，读 subscription-userinfo 与 Content-Disposition 文件名。
    public static let httpFetch: @Sendable (URL) async throws -> FetchedBody = { url in
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("clash.meta/zephyr-mobile", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ZephyrError(code: .subscriptionFetchFailed, message: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw ZephyrError(code: .subscriptionInvalid, message: "not utf-8")
        }
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
        return FetchedBody(body: body, userInfo: http.value(forHTTPHeaderField: "subscription-userinfo"),
                           fileName: disposition.flatMap { CoreEngine.contentDispositionFileName($0) })
    }

    static func contentDispositionFileName(_ v: String) -> String? {
        for part in v.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.lowercased().hasPrefix("filename*="), let r = part.range(of: "''") {
                return String(part[r.upperBound...]).removingPercentEncoding
            }
            if part.lowercased().hasPrefix("filename=") {
                return String(part.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    static func httpURL(_ s: String) -> URL? {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil else { return nil }
        return u
    }

    static func defaultName(_ url: URL?) -> String {
        guard let url else { return "本地配置" }
        guard let host = url.host else { return "新订阅" }
        let parts = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        let base = parts.count >= 2 ? parts[parts.count - 2] : (parts.first ?? "新订阅")
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    /// 隧道启动前由 App 调用：当前订阅 + 设置 → mihomo YAML（unix socket 控制口、系统 TUN fd 由扩展填）。
    public func runtimeConfig(subscriptionId: String, options: RuntimeOptions) async throws -> String {
        guard let c = core else { throw ZephyrError(code: .notRunning, message: "core unavailable") }
        return try await run(.subscriptionInvalid) { try c.runtimeConfig(subscriptionId: subscriptionId, options: options) }
    }

    /// iOS 隧道启动前由 App 调用：当前订阅 + 设置 → mihomo YAML，原子写到 `url`（App Group/core/config.yaml）。
    /// tun.file-descriptor 写哨兵 -1，由 PacketTunnel 拿到 utun fd 后替换（扩展不链接 Rust 核心，省 NE 内存）。
    public func writeTunnelConfig(to url: URL, controllerSocket: String) async throws {
        guard let c = core else { throw ZephyrError(code: .notRunning, message: "core unavailable") }
        guard let id = await runQuiet({ c.subscriptions() }).first?.id else {
            throw ZephyrError(code: .subscriptionInvalid, message: "请先添加订阅")
        }
        var settingsIterator = fallback.settings().makeAsyncIterator()
        let s = await settingsIterator.next()
        var modeIterator = connectionState().makeAsyncIterator()
        let mode = await modeIterator.next()?.mode ?? .rule
        let options = CoreEngine.runtimeOptions(settings: s, mode: mode, controllerSocket: controllerSocket)
        let yaml = try await run(.subscriptionInvalid) { try c.runtimeConfig(subscriptionId: id, options: options) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(yaml.utf8).write(to: url, options: .atomic)
    }

    static func runtimeOptions(settings s: ZephyrKit.Settings?, mode: ZephyrKit.ProxyMode, controllerSocket: String) -> RuntimeOptions {
        let dns = s?.dns ?? DnsSettings()
        let tun = s?.tun ?? TunSettings()
        let stack: TunStackKind = switch tun.stack { case .system: .system; case .gvisor: .gvisor; case .mixed: .mixed }
        let coreMode: ProxyMode = switch mode { case .rule: .rule; case .global: .global; case .direct: .direct }
        return RuntimeOptions(
            dns: DnsConfig(fakeIp: dns.fakeIp, nameservers: dns.nameservers, fallback: dns.fallback, ipv6: dns.ipv6),
            tun: TunConfig(stack: stack, mtu: tun.mtu, ipv6: tun.ipv6, strictRoute: tun.strictRoute, fileDescriptor: -1),
            mode: coreMode, controllerSocket: controllerSocket, findProcess: false, logLevel: "warning",
            localProxy: localProxy(settings: s))
    }

    /// 本地代理（契约 §14.z）：只绑 127.0.0.1；开鉴权时用本机生成并保存的凭据。
    static func localProxy(settings s: ZephyrKit.Settings?, defaults: UserDefaults = .standard) -> LocalProxy? {
        guard let s, s.localProxyEnabled, (1024...65535).contains(Int(s.localProxyPort)) else { return nil }
        return LocalProxy(port: UInt16(s.localProxyPort), auth: s.localProxyAuth ? localProxyCredential(defaults: defaults) : nil)
    }

    /// "zephyr:<随机 24 位>"，首次生成后保存；UI 在设置页展示给需要配置的 App。
    public static func localProxyCredential(defaults: UserDefaults = .standard) -> String {
        let key = "zephyr.localProxyCredential"
        if let v = defaults.string(forKey: key), v.contains(":") { return v }
        let alphabet = Array("abcdefghijkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789")
        var rng = SystemRandomNumberGenerator()
        let pass = String((0..<24).map { _ in alphabet.randomElement(using: &rng)! })
        let v = "zephyr:\(pass)"
        defaults.set(v, forKey: key)
        return v
    }

    // MARK: - §8 连接、日志、设置、存储

    public func activeConnections() -> AsyncStream<[ZephyrKit.ConnectionInfo]> {
        if let t = tunnel { return liveConnections(t) }
        return fallback.activeConnections()
    }
    public func closeConnection(id: String) async throws {
        if let t = tunnel { return try await liveClose(t, id: id) }
        try await fallback.closeConnection(id: id)
    }
    public func closeAll() async throws {
        if let t = tunnel { return try await liveClose(t, id: nil) }
        try await fallback.closeAll()
    }
    public func logs(minLevel: LogLevel) -> AsyncStream<LogLine> { fallback.logs(minLevel: minLevel) }
    public func settings() -> AsyncStream<ZephyrKit.Settings> { fallback.settings() }
    public func updateSettings(patch: ZephyrKit.Settings) async throws { try await fallback.updateSettings(patch: patch) }

    public func storage() async -> ZephyrKit.StorageInfo {
        guard let c = core else { return await fallback.storage() }
        let s = await runQuiet { c.storageInfo() }
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: CoreEngine.defaultDataDir().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return ZephyrKit.StorageInfo(nodesBytes: s.nodesBytes, rulesBytes: s.rulesBytes, freeBytes: free)
    }

    // MARK: - §9 命令搜索

    public func commandSuggestions(input: String) async -> [CommandSuggestion] { await fallback.commandSuggestions(input: input) }

    // MARK: - 映射

    static func just<T: Sendable>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v); $0.finish() } }

    static let regionNames: [String: String] = Dictionary(uniqueKeysWithValues: MockNodes.regions.map { ($0.code, $0.name) })

    static func section(_ s: RegionSection) -> ZephyrKit.RegionSection {
        ZephyrKit.RegionSection(region: s.region, name: regionNames[s.region] ?? s.region, count: Int64(s.count), rowOffset: Int64(s.rowOffset))
    }

    static func row(_ r: NodeRow) -> NodeSummary {
        NodeSummary(id: r.id, name: r.name, region: r.region, city: r.city, carrier: r.carrier, tag: r.tag,
                    protocol: r.protocol, multiplier: r.multiplier)
    }

    static func kind(_ k: LayerKind) -> ZephyrKit.LayerKind {
        switch k { case .override: .override; case .subscription: .subscription; case .domain: .domain; case .ip: .ip }
    }

    static func diff(_ d: SubscriptionDiff) -> ZephyrKit.SubscriptionDiff {
        ZephyrKit.SubscriptionDiff(addedNodes: d.addedNodes, removedNodes: d.removedNodes, ruleChanges: d.ruleChanges,
                                   overridesKept: d.overridesKept, scenesRetested: d.scenesRetested)
    }

    static func sub(_ s: Subscription) -> ZephyrKit.Subscription {
        ZephyrKit.Subscription(id: s.id, name: s.name, url: s.url, nodeCount: s.nodeCount, usedBytes: s.usedBytes,
                               totalBytes: s.totalBytes, remainingBytes: s.remainingBytes, expiresAt: s.expiresAt,
                               updatedAt: s.updatedAt, autoUpdateHours: s.autoUpdateHours, lastDiff: s.lastDiff.map(diff))
    }

    static let unselected = NodeSummary(id: NodeId.max, name: "未选择", region: "", protocol: "")

    static func scene(_ s: Scene) -> ZephyrKit.Scene {
        let kind: ZephyrKit.SceneKind = switch s.kind { case .ai: .ai; case .video: .video; case .other: .other; case .custom: .custom }
        let source: ZephyrKit.SceneSource = switch s.source { case .auto: .auto; case .manual: .manual; case .subscriptionGroup: .subscriptionGroup }
        var selected = s.selected.map(row) ?? unselected
        if let ms = s.selectedLatencyMs, ms > 0 { selected.latencyMs = ms }
        return ZephyrKit.Scene(id: s.id, kind: kind, name: s.name, available: s.available, selected: selected, exitIp: s.exitIp,
                               source: source, testedAt: s.testedAt, note: s.note,
                               exceptions: s.exceptions.compactMap { e in e.node.map { ZephyrKit.SceneException(app: e.app, node: row($0)) } },
                               services: s.services.map { ZephyrKit.ServiceHealth(appId: $0.appId, name: $0.name, ok: $0.ok, checkedAt: $0.checkedAt) })
    }
}

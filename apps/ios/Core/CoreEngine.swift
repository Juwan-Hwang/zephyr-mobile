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

    let core: MobileCore?
    private let fallback: any ZephyrEngine
    private let mockData: Bool
    let clock: @Sendable () -> Int64
    private let fetcher: @Sendable (URL) async throws -> FetchedBody
    /// 二进制下载（geosite.dat / geoip.dat）：(远端, 本地目标)。
    private let downloader: @Sendable (URL, URL) async throws -> Void
    private let queue = DispatchQueue(label: "app.zephyr.core", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()

    // 受 lock 保护
    private var nodesReady: Bool?
    private var rulesReady: Bool?
    private var queries: [UInt64: String] = [:]
    private var remapped: [UInt64: UInt64] = [:]
    private var queryOrder: [UInt64] = []
    private var subsWatchers: [UUID: AsyncStream<[ZephyrKit.Subscription]>.Continuation] = [:]
    private var sceneWatchers: [UUID: AsyncStream<[ZephyrKit.Scene]>.Continuation] = [:]
    /// 场景快照序号：每次读取前取号，发布时只接受比已发布更新的号，
    /// 避免轮询中途读到的旧快照在 bumpScenes 发布新状态后再覆盖回去（PR #38 评审）。
    private var sceneReadSeq = 0
    private var scenePublishedSeq = 0
    var latencyWatchers: [UUID: AsyncStream<[LatencyUpdate]>.Continuation] = [:]
    private var settingsWatchers: [UUID: AsyncStream<ZephyrKit.Settings>.Continuation] = [:]
    private var globalWatchers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var cachedSettings: ZephyrKit.Settings?
    private let settingsURL: URL
    private var samples: [TrafficSample] = []
    /// 流量流的共享上游（AppModel / SharedStatePublisher 共用一次轮询）。
    let trafficBroadcast = SharedBroadcast<TrafficSample>()
    /// 场景与连接状态是状态流：App 内多处订阅（AppModel、SharedStatePublisher、LibraryModel…）共享同一个上游，
    /// 场景只有一份 5 s 轮询（REVIEW-Q2 X-P1-3）；晚到者立即拿到最新值。
    let sceneBroadcast = SharedBroadcast<[ZephyrKit.Scene]>(replayLatest: true)
    let connectionBroadcast = SharedBroadcast<ConnectionState>(replayLatest: true)
    /// 场景出口探测的共享上游：无论几处订阅只跑一份探测循环。
    let failoverBroadcast = SharedBroadcast<SceneFailoverNotice>()
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
                downloader: (@Sendable (URL, URL) async throws -> Void)? = nil,
                tunnel: (any TunnelPort)? = nil) {
        let dir = dataDir ?? CoreEngine.defaultDataDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.core = try? MobileCore(dataDir: dir.path)
        self.settingsURL = dir.appendingPathComponent("settings.json")
        self.fallback = fallback ?? MockEngine(clock: .live)
        self.mockData = mockData
        self.clock = clock
        self.fetcher = fetcher ?? CoreEngine.httpFetch
        self.downloader = downloader ?? CoreEngine.httpDownload
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
    func run<T: Sendable>(_ notFound: ErrorCode = .nodeNotFound, _ body: @escaping @Sendable () throws -> T) async throws -> T {
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

    func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private func invalidateNodes() { locked { nodesReady = nil } }

    /// 核心没有节点数据时的回落：只有 Debug / 演示（mockData）才用 MockEngine 的确定性数据，
    /// Release 抛出明确错误，绝不把假数据当真的写给用户（REVIEW-Q2 X-P0-2）。
    private func demo<T>(_ code: ErrorCode, _ body: () async throws -> T) async throws -> T {
        guard mockData else { throw ZephyrError(code: code, message: "节点库为空") }
        return try await body()
    }

    /// 有节点数据时返回核心，否则 nil（调用方回落）。
    func nodes() async -> MobileCore? {
        guard let c = core else { return nil }
        if let ready = locked({ nodesReady }) { return ready ? c : nil }
        let ok = await runQuiet { ((try? c.nodeIndex())?.total ?? 0) > 0 }
        locked { nodesReady = ok }
        return ok ? c : nil
    }

    private func rules() async -> MobileCore? {
        guard let c = core else { return nil }
        if locked({ rulesReady }) == true { return c }
        // 只缓存"已就绪"：导入订阅后核心会编译订阅规则层，之后必须能看到。
        let ok = await runQuiet { c.ruleStats().total > 0 }
        if ok { locked { rulesReady = true } }
        return ok ? c : nil
    }

    // MARK: - §1 连接与模式（VPN 生命周期属 PacketTunnel；此处转发）

    public func connectionState() -> AsyncStream<ConnectionState> {
        if let t = tunnel {
            return connectionBroadcast.subscribe { [weak self] in
                guard let self else { return AsyncStream { $0.finish() } }
                return self.liveConnectionState(t)
            }
        }
        return fallback.connectionState()
    }

    /// 隧道状态 + 全局出口节点：扩展写的状态里没有 globalNodeId，冷启动后全局卡会没有节点（REVIEW-Q2 X-P1）。
    /// 全局模式下由核心补上 globalNode()；setGlobalNode 后用 globalWatchers 重发一次。
    private func liveConnectionState(_ t: any TunnelPort) -> AsyncStream<ConnectionState> {
        guard let c = core else { return t.states() }
        let id = UUID()
        let (nudges, nudge) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        locked { globalWatchers[id] = nudge }
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { k in
            let latest = LockedBox<ConnectionState?>(nil)
            let enrich: @Sendable (ConnectionState) -> ConnectionState = { s in
                var s = s
                if s.mode == .global { s.globalNodeId = c.globalNode() } else { s.globalNodeId = nil }
                return s
            }
            let states = Task {
                for await s in t.states() {
                    latest.set(s)
                    k.yield(enrich(s))
                }
                k.finish()
            }
            let renudge = Task {
                for await _ in nudges {
                    if let s = latest.get() { k.yield(enrich(s)) }
                }
            }
            k.onTermination = { [weak self] _ in
                states.cancel(); renudge.cancel(); nudge.finish()
                self?.locked { _ = self?.globalWatchers.removeValue(forKey: id) }
            }
        }
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
    /// 全局模式出口：核心记下节点（不在配置里则需重载），然后总是在 mihomo 的 GLOBAL 组里选中它。
    public func setGlobalNode(id: NodeId) async throws -> ZephyrKit.ExitChange {
        guard let c = await nodes() else { return try await demo(.nodeNotFound) { try await fallback.setGlobalNode(id: id) } }
        let x = try await run(.nodeNotFound) { try c.previewGlobalChange(nodeId: id) }
        let apply = try await run(.nodeNotFound) { try c.setGlobalNode(nodeId: id) }
        if let t = tunnel {
            // reloadTunnelIfRunning 自己处理已连接 / 连接中；选择出口在连上后执行（连接中排队）
            if apply.needsReload { await reloadTunnelIfRunning(t) }
            let sock = t.controllerSocketPath, group = apply.group, member = apply.member
            let select: @Sendable () async -> Void = { [weak self] in
                _ = try? await self?.mihomo(sock) { try $0.selectInGroup(group: group, member: member) }
            }
            switch await t.currentStatus() {
            case .connected: await select()
            case .connecting: afterConnect(t, select)
            default: break
            }
        }
        for w in locked({ Array(globalWatchers.values) }) { w.yield() }
        return ZephyrKit.ExitChange(sceneId: nil, fromRegion: x.fromRegion ?? "", fromIp: x.fromIp, toRegion: x.toRegion,
                                    toIp: x.toIp, affectedApps: x.affectedApps, unchangedApps: x.unchangedApps)
    }

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
    /// 今日用量：字节与在线时长来自扩展的账本（UsageLedger）；地区数 = 当前各场景/全局出口的不同地区；
    /// 最快 = 延迟缓存里有效期内（设置“延迟结果保留”）最快的节点。
    public func usageToday() async -> UsageSummary {
        guard let t = tunnel else { return await fallback.usageToday() }
        let ledger = await t.usageToday()
        let hourly = ledger?.hourly ?? Array(repeating: 0, count: 24)
        var regions = Set((try? await readScenes())?.compactMap { $0.selected.region.isEmpty ? nil : $0.selected.region } ?? [])
        var fastest: Int32?
        if let c = core {
            let now = clock()
            let fresh = latencyFreshMillis
            let top = await runQuiet { (try? c.fastestNodes(query: "", limit: 1, nowMillis: now, maxAgeMillis: fresh)) ?? [] }
            fastest = top.first.map(\.latencyMs).flatMap { $0 > 0 ? $0 : nil }
            if let g = c.globalNode(), let r = try? await run(.nodeNotFound, { try c.nodeDetail(id: g) }) { regions.insert(r.row.region) }
        }
        return UsageSummary(todayBytes: hourly.reduce(0, +), regionsToday: Int32(regions.count),
                            onlineMillisToday: ledger?.onlineMillis ?? 0, fastestLatencyMs: fastest, hourly: hourly)
    }

    // MARK: - §3 场景

    public func scenes() -> AsyncStream<[ZephyrKit.Scene]> {
        guard core != nil else { return mockData ? fallback.scenes() : CoreEngine.just([]) }
        return sceneBroadcast.subscribe { [weak self] in
            guard let self else { return AsyncStream { $0.finish() } }
            return self.pollScenes()
        }
    }

    /// 场景上游：只由 sceneBroadcast 在 0→1 个订阅者时创建一次。
    private func pollScenes() -> AsyncStream<[ZephyrKit.Scene]> {
        let id = UUID()
        let (stream, cont) = AsyncStream<[ZephyrKit.Scene]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        locked { sceneWatchers[id] = cont }
        let task = Task { [weak self] in
            guard let self else { return }
            if self.mockData, await self.nodes() == nil {
                for await v in self.fallback.scenes() { cont.yield(v) }
                return
            }
            // 空库先给空数组；之后每轮重新检查节点库（首次导入订阅会 invalidateNodes），有数据就恢复轮询（REVIEW-Q2 X-P1）。
            var last: [ZephyrKit.Scene]?
            while !Task.isCancelled {
                if await self.nodes() != nil {
                    let seq = self.locked { () -> Int in self.sceneReadSeq += 1; return self.sceneReadSeq }
                    if let v = try? await self.readScenes(), v != last {
                        let fresh = self.locked { () -> Bool in
                            guard seq > self.scenePublishedSeq else { return false }
                            self.scenePublishedSeq = seq
                            cont.yield(v)
                            return true
                        }
                        if fresh { last = v }
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                } else {
                    if last != [] { last = []; cont.yield([]) }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
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

    func bumpScenes() async {
        let seq = locked { () -> Int in sceneReadSeq += 1; return sceneReadSeq }
        guard let v = try? await readScenes() else { return }
        locked {
            guard seq > scenePublishedSeq else { return }   // 更新的读取已发布
            scenePublishedSeq = seq
            for c in sceneWatchers.values { c.yield(v) }
        }
    }

    public func sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary] {
        guard let c = await nodes() else { return mockData ? try await fallback.sceneCandidates(sceneId: sceneId, region: region) : [] }
        let now = clock()
        return try await run(.sceneNotFound) { try c.sceneCandidates(sceneId: sceneId, region: region, nowMillis: now) }
            .map { r in var s = CoreEngine.row(r.row); s.latencyMs = r.latencyMs > 0 ? r.latencyMs : nil; return s }
    }

    public func previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ZephyrKit.ExitChange {
        guard let c = await nodes() else { return try await demo(.sceneNotFound) { try await fallback.previewSceneChange(sceneId: sceneId, nodeId: nodeId) } }
        let x = try await run(.sceneNotFound) { try c.previewSceneChange(sceneId: sceneId, nodeId: nodeId) }
        return ZephyrKit.ExitChange(sceneId: x.sceneId, fromRegion: x.fromRegion ?? "", fromIp: x.fromIp, toRegion: x.toRegion,
                                    toIp: x.toIp, affectedApps: x.affectedApps, unchangedApps: x.unchangedApps)
    }

    public func applySceneChange(sceneId: String, nodeId: NodeId) async throws {
        guard let c = await nodes() else { return try await demo(.sceneNotFound) { try await fallback.applySceneChange(sceneId: sceneId, nodeId: nodeId) } }
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
        guard let c = await nodes() else { return try await demo(.sceneNotFound) { try await fallback.retestScene(sceneId: sceneId) } }
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
        guard let c = await nodes() else { return try await demo(.sceneNotFound) { try await fallback.setSceneSource(sceneId: sceneId, source: source) } }
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
        guard let c = core else { return try await demo(.internal) { try await fallback.overrideHost(host: host, target: target, sceneId: sceneId, persistent: persistent) } }
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
        let fresh = latencyFreshMillis
        let tested = await runQuiet { c.testedCount(nowMillis: self.clock(), maxAgeMillis: fresh) }
        return ZephyrKit.NodeIndex(total: Int64(i.total), sections: i.sections.map(CoreEngine.section), testedCount: Int64(tested))
    }

    /// 记录 token → 查询（过期 token 重建用）。只留最近 64 个，避免每次搜索都让两张表无限增长（REVIEW-Q2 P2）。
    private func rememberQuery(token: UInt64, query: String, replacing original: UInt64? = nil) {
        locked {
            queries[token] = query
            if let original { remapped[original] = token }
            queryOrder.append(token)
            while queryOrder.count > 64 {
                let old = queryOrder.removeFirst()
                queries.removeValue(forKey: old)
                remapped = remapped.filter { $0.key != old && $0.value != old }
            }
        }
    }

    public func queryNodes(query: String) async throws -> ZephyrKit.NodeQueryResult {
        guard let c = await nodes() else {
            if mockData { return try await fallback.queryNodes(query: query) }
            return ZephyrKit.NodeQueryResult(query: query, total: 0, sections: [], highlights: [], tookMicros: 0, token: 0)
        }
        let r = try await run { try c.queryNodes(query: query) }
        rememberQuery(token: r.token, query: query)
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
            rememberQuery(token: fresh, query: q, replacing: original)
            page = try await run { try c.nodeRows(token: fresh, offset: off, limit: lim) }
        }
        let ids = page.rows.map(\.id)
        let now = clock()
        let lat = await runQuiet { c.cachedLatencies(ids: ids, nowMillis: now, maxAgeMillis: 30 * 60 * 1000) }
        let rows = zip(page.rows, lat).map { r, ms -> NodeSummary in var s = CoreEngine.row(r); s.latencyMs = ms; return s }
        return ZephyrKit.NodePage(rows: rows, offset: Int64(page.offset), total: Int64(page.total))
    }

    /// 延迟结果的有效期 = 设置里的“延迟结果保留”（REVIEW-Q2 X-P1-5，此前写死 24 h）。
    var latencyFreshMillis: Int64 { Int64(max(1, loadSettings().latencyTtlHours)) * 3_600_000 }

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
    /// 隧道未连接时改测 TCP 握手（契约 §14.u，CoreEngine+TcpPing.swift）。
    public func testLatency(ids: [NodeId]) async {
        guard let c = await nodes() else { if mockData { await fallback.testLatency(ids: ids) }; return }
        var seen = Set<NodeId>()
        let unique = ids.filter { seen.insert($0).inserted }
        guard let t = tunnel, await isTunnelConnected(t) else { return await tcpPing(c, ids: unique) }
        for start in stride(from: 0, to: unique.count, by: 512) {
            if Task.isCancelled { return }
            let chunk = Array(unique[start..<min(start + 512, unique.count)])
            guard let json = try? await run(.nodeNotFound, { try c.latencyTestBatch(ids: chunk) }), json != "[]",
                  let out = await t.urlTest(proxiesJSON: json, url: "https://www.gstatic.com/generate_204", timeoutMs: 5000) else { continue }
            let now = clock()
            guard let samples = try? await run(.nodeNotFound, { try c.recordUrlTest(resultJson: out, nowMillis: now) }), !samples.isEmpty else { continue }
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
        guard let core else { return try await fallback.testRule(input: input) }
        if mockData, await rules() == nil { return try await fallback.testRule(input: input) }
        let c = core
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
        scheduleRuleProviderRefresh()
        // 首个订阅导入后就写出配置：控制中心 / 小组件的连接开关由扩展直接启动隧道，不能等到 App 里点连接（X-P1-6）。
        if let t = tunnel { await reloadTunnelIfRunning(t) }
        return CoreEngine.sub(s)
    }

    /// 规则集（契约 §14.w）：后台拉取到期的 http 规则集并编译为规则页第 3 层起。返回成功编译的个数。
    /// 真实路由由扩展里的 mihomo 自己拉取；这里只服务规则页计数、testRule 与命令搜索。
    @discardableResult
    public func refreshRuleProviders(force: Bool = false) async -> Int {
        guard let c = core else { return 0 }
        let now = clock()
        let due = await runQuiet { c.ruleProviders(nowMillis: now) }.filter { force || $0.due }
        var ok = 0
        for p in due where p.format != "mrs" {
            if Task.isCancelled { break }
            guard let url = URL(string: p.url), let got = try? await fetch(url) else { continue }
            let at = clock()
            if (try? await run(.ruleInputInvalid, { try c.compileRuleProvider(name: p.name, body: got.body, nowMillis: at) })) != nil { ok += 1 }
        }
        ok += await refreshGeo(c, force: force)
        if ok > 0 { locked { rulesReady = nil } }
        return ok
    }

    /// GEOSITE / GEOIP：下载订阅用到的 dat 到核心给的路径，再由核心抽取分类编译成层（每周到期）。
    private func refreshGeo(_ c: MobileCore, force: Bool) async -> Int {
        var ok = 0
        for s in await runQuiet({ c.geoSources(nowMillis: self.clock()) }) where force || s.due {
            if Task.isCancelled { break }
            guard let url = URL(string: s.url), url.scheme == "https" else { continue }
            let dest = URL(fileURLWithPath: s.path)
            do { try await downloader(url, dest) } catch { continue }
            let at = clock()
            if let n = try? await run(.ruleInputInvalid, { try c.compileGeo(kind: s.kind, nowMillis: at) }) { ok += Int(n) }
        }
        return ok
    }

    /// 下载到临时文件后原子替换，失败不破坏旧文件。
    public static let httpDownload: @Sendable (URL, URL) async throws -> Void = { url, dest in
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.setValue("clash.meta/zephyr-mobile", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            try? FileManager.default.removeItem(at: tmp)
            throw URLError(.badServerResponse)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dest)
        }
    }

    private func scheduleRuleProviderRefresh() {
        Task.detached(priority: .utility) { [weak self] in await self?.refreshRuleProviders() }
    }

    public func previewUpdate(id: String) async throws -> ZephyrKit.SubscriptionDiff {
        guard let c = core else { return try await fallback.previewUpdate(id: id) }
        let got = try await fetchFor(id, c)
        let fetched = FetchedSubscription(body: got.body, userinfo: got.userInfo, nowMillis: clock())
        return CoreEngine.diff(try await run(.subscriptionInvalid) { try c.previewSubscriptionUpdate(id: id, fetched: fetched) })
    }

    public func updateSubscription(id: String) async throws -> ZephyrKit.SubscriptionDiff {
        guard core != nil else { return try await fallback.updateSubscription(id: id) }
        let d = try await applyUpdate(id: id)
        if let t = tunnel { await reloadTunnelIfRunning(t) }
        return d
    }

    /// 全部更新：只在最后重载一次隧道（此前每个订阅各重载一次）；单个失败不影响其余，
    /// 但全部失败时抛出第一个错误，让界面能提示（此前 `try?` 吞掉，显示“已更新 0 个订阅”）。
    public func updateAll() async throws -> [ZephyrKit.SubscriptionDiff] {
        guard let c = core else { return try await fallback.updateAll() }
        let ids = await runQuiet { c.subscriptions() }.filter { $0.url != nil }.map(\.id)
        var out: [ZephyrKit.SubscriptionDiff] = []
        var firstError: Error?
        for id in ids {
            try Task.checkCancellation()
            do { out.append(try await applyUpdate(id: id)) } catch is CancellationError { throw CancellationError() } catch {
                if firstError == nil { firstError = error }
            }
        }
        if !out.isEmpty, let t = tunnel { await reloadTunnelIfRunning(t) }
        if out.isEmpty, let firstError { throw firstError }
        return out
    }

    /// 取回并应用一个订阅的新内容；不重载隧道（由调用方决定何时重载）。
    private func applyUpdate(id: String) async throws -> ZephyrKit.SubscriptionDiff {
        guard let c = core else { throw ZephyrError(code: .subscriptionInvalid, message: "no core") }
        let got = try await fetchFor(id, c)
        let fetched = FetchedSubscription(body: got.body, userinfo: got.userInfo, nowMillis: clock())
        let d = try await run(.subscriptionInvalid) { try c.updateSubscription(id: id, fetched: fetched, progress: nil) }
        invalidateNodes()
        await publishSubs()
        await bumpScenes()
        scheduleRuleProviderRefresh()
        return CoreEngine.diff(d)
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
        let s = await currentSettings()
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
    /// 标准 UserDefaults 时存钥匙串（REVIEW-Q2：凭据不落 plist），并把旧版 UserDefaults 里的值迁移过去；
    /// 自定义 defaults（单测）或钥匙串不可用时存 defaults。
    public static func localProxyCredential(defaults: UserDefaults = .standard) -> String {
        let key = "zephyr.localProxyCredential"
        let useKeychain = defaults === UserDefaults.standard
        if useKeychain, let v = KeychainStore.read(key), v.contains(":") { return v }
        if let v = defaults.string(forKey: key), v.contains(":") {
            if useKeychain, KeychainStore.write(key, v) { defaults.removeObject(forKey: key) }
            return v
        }
        let alphabet = Array("abcdefghijkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789")
        var rng = SystemRandomNumberGenerator()
        let pass = String((0..<24).map { _ in alphabet.randomElement(using: &rng)! })
        let v = "zephyr:\(pass)"
        if !(useKeychain && KeychainStore.write(key, v)) { defaults.set(v, forKey: key) }
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
    public func logs(minLevel: LogLevel) -> AsyncStream<LogLine> {
        if let t = tunnel { return liveLogs(t, minLevel: minLevel) }
        return mockData ? fallback.logs(minLevel: minLevel) : AsyncStream { $0.finish() }
    }
    /// 设置落盘（dataDir/settings.json）。无核心时回落 fallback；首次无文件用 `defaultSettings`。
    public func settings() -> AsyncStream<ZephyrKit.Settings> {
        guard core != nil else { return fallback.settings() }
        let id = UUID()
        let (stream, cont) = AsyncStream<ZephyrKit.Settings>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let current = loadSettings()
        locked { settingsWatchers[id] = cont }
        cont.yield(current)
        cont.onTermination = { [weak self] _ in self?.locked { _ = self?.settingsWatchers.removeValue(forKey: id) } }
        return stream
    }

    public func updateSettings(patch: ZephyrKit.Settings) async throws {
        guard core != nil else { return try await fallback.updateSettings(patch: patch) }
        guard (1...65535).contains(patch.localProxyPort), patch.latencyTtlHours > 0, patch.autoUpdateHours > 0,
              (576...9000).contains(patch.tun.mtu) else {
            throw ZephyrError(code: .internal, message: "invalid settings value")
        }
        let old = loadSettings()
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SharedJSON.encoder.encode(patch).write(to: settingsURL, options: .atomic)
        } catch {
            throw ZephyrError(code: .storageFull, message: "\(error)")
        }
        let watchers = locked { () -> [AsyncStream<ZephyrKit.Settings>.Continuation] in
            cachedSettings = patch
            return Array(settingsWatchers.values)
        }
        for w in watchers { w.yield(patch) }
        // 影响 mihomo 配置的字段变了：隧道运行中热重载。
        if let t = tunnel, CoreEngine.affectsRuntime(old, patch) { await reloadTunnelIfRunning(t) }
        if let t = tunnel, old.onDemand != patch.onDemand || old.trustedWifi != patch.trustedWifi
            || old.disconnectOnTrusted != patch.disconnectOnTrusted {
            await t.applyOnDemand(onDemand: patch.onDemand, trustedNetworks: patch.trustedWifi,
                                  disconnectOnTrusted: patch.disconnectOnTrusted, create: false)
        }
    }

    static func affectsRuntime(_ a: ZephyrKit.Settings, _ b: ZephyrKit.Settings) -> Bool {
        a.dns != b.dns || a.tun != b.tun || a.localProxyEnabled != b.localProxyEnabled
            || a.localProxyPort != b.localProxyPort || a.localProxyAuth != b.localProxyAuth
    }

    func currentSettings() async -> ZephyrKit.Settings? {
        guard core != nil else {
            var it = fallback.settings().makeAsyncIterator()
            return await it.next()
        }
        return loadSettings()
    }

    private func loadSettings() -> ZephyrKit.Settings {
        if let s = locked({ cachedSettings }) { return s }
        let s = (try? Data(contentsOf: settingsURL)).flatMap { try? SharedJSON.decoder.decode(ZephyrKit.Settings.self, from: $0) }
            ?? CoreEngine.defaultSettings
        locked { cachedSettings = s }
        return s
    }

    /// 首次安装的设置：本地代理关、不信任任何 Wi-Fi、仅 Wi-Fi 下自动测速与更新。
    public static let defaultSettings = ZephyrKit.Settings(
        onDemand: false, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890, localProxyAuth: true,
        testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12, updateOnWifiOnly: true, showChangesBeforeUpdate: true,
        dns: DnsSettings(), tun: TunSettings(), accent: .blue, appearance: .system, shareAnonymousPattern: false,
        localProxyEnabled: false)

    public func storage() async -> ZephyrKit.StorageInfo {
        guard let c = core else { return await fallback.storage() }
        let s = await runQuiet { c.storageInfo() }
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: CoreEngine.defaultDataDir().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return ZephyrKit.StorageInfo(nodesBytes: s.nodesBytes, rulesBytes: s.rulesBytes, freeBytes: free)
    }

    // MARK: - §9 命令搜索

    public func commandSuggestions(input: String) async -> [CommandSuggestion] {
        guard await nodes() != nil else { return mockData ? await fallback.commandSuggestions(input: input) : [] }
        return await liveCommandSuggestions(input: input)
    }

    /// 结果集里有效期（设置“延迟结果保留”）内最快的节点（带延迟）；没有测速数据为 nil。
    func fastest(query: String) async -> NodeSummary? {
        guard let c = core else { return nil }
        let now = clock()
        let fresh = latencyFreshMillis
        let top = await runQuiet { (try? c.fastestNodes(query: query, limit: 1, nowMillis: now, maxAgeMillis: fresh)) ?? [] }
        guard let r = top.first, r.latencyMs > 0 else { return nil }
        var s = CoreEngine.row(r.row)
        s.latencyMs = r.latencyMs
        return s
    }

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

/// 设置文件的 JSON 编解码（键名用模型自带的 snake_case CodingKeys）。
enum SharedJSON {
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder = JSONDecoder()
}

/// 小型加锁盒子：在 @Sendable 闭包间共享最新值。
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
}

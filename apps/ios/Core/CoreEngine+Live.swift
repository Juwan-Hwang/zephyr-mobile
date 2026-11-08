// CoreEngine 的实时部分：连接、流量、策略组、连接列表来自 PacketTunnel 里的 mihomo。
//
// - 隧道生命周期经 `TunnelPort`（App 层实现：NETunnelProviderManager + provider message），本模块不依赖 NetworkExtension。
// - 策略组 / 连接 / 选择经核心的 `MihomoClient`（unix socket REST，App Group/zm.sock），阻塞 FFI 一律在后台队列。
// - 没有 TunnelPort（模拟器、单测）时整段回落 fallback，行为与之前一致。
// - 轮询：流量 1 Hz、连接 1 Hz、策略组 3 s；订阅方取消即停。未连接时给空，不报错。

import Foundation
import ZephyrKit

/// App 层提供的系统隧道入口（真机）。
public protocol TunnelPort: AnyObject, Sendable {
    /// 当前状态，不订阅。默认实现取 `states()` 首个值，2 s 内没有值视为 disconnected（不会挂起调用方）。
    func currentStatus() async -> ConnectionStatus
    /// 隧道状态（含模式与起始时间），首个值为当前状态。
    func states() -> AsyncStream<ConnectionState>
    func start() async throws
    func stop() async throws
    func setMode(_ mode: ZephyrKit.ProxyMode) async throws
    /// 实时速率（字节/秒）；未连接为 nil。
    func rate() async -> (up: Int64, down: Int64)?
    /// 让扩展按 `configURL` 的新内容热重载。
    func reloadConfig() async throws
    /// mihomo external-controller-unix 路径。
    var controllerSocketPath: String { get }
    /// App 写、扩展读的 mihomo 配置路径。
    var configURL: URL { get }
    /// 批量延迟测试（扩展里 zm_url_test）；输入为核心 latencyTestBatch 的 JSON，返回 zm_url_test 原样 JSON。
    /// 隧道未连接或不支持时为 nil。
    func urlTest(proxiesJSON: String, url: String, timeoutMs: Int32) async -> String?
    /// 扩展记的今日用量（字节、24 小时桶、在线毫秒）；没有账本为 nil。
    func usageToday() async -> (hourly: [Int64], onlineMillis: Int64)?
    /// zm_logs 增量 JSON；未连接为 nil。
    func logs(since: Int64, minLevel: String, limit: Int32) async -> String?
    /// 系统按需规则（按需连接 / 受信任 Wi‑Fi 自动断开）。`create == false` 时 VPN 配置尚未创建就什么都不做（避免提前弹授权）。
    /// 默认不支持（单测、模拟器）。
    func applyOnDemand(onDemand: Bool, trustedNetworks: [String], disconnectOnTrusted: Bool, create: Bool) async
}

public extension TunnelPort {
    func applyOnDemand(onDemand: Bool, trustedNetworks: [String], disconnectOnTrusted: Bool, create: Bool) async {}
}

extension CoreEngine {

    // MARK: 连接

    func liveConnect(_ t: any TunnelPort) async throws {
        try await writeTunnelConfig(to: t.configURL, controllerSocket: t.controllerSocketPath)
        if let s = await currentSettings() {
            await t.applyOnDemand(onDemand: s.onDemand, trustedNetworks: s.trustedWifi, disconnectOnTrusted: s.disconnectOnTrusted, create: true)
        }
        try await t.start()
    }

    /// 隧道在跑时：重写配置并让扩展热重载；没在跑则什么都不做（下次连接时 liveConnect 会重写）。
    func isTunnelConnected(_ t: any TunnelPort) async -> Bool {
        await t.currentStatus() == .connected
    }

    /// 配置变了：总是把新配置写到 App Group（断开时也写——控制中心 / 小组件的连接开关由扩展进程直接启动隧道，
    /// 读到的必须是最新配置，REVIEW-Q2 X-P1-6）。已连接：写完让扩展热重载。正在连接（含 reasserting）：扩展可能已在启动早期读走旧配置，
    /// 而连接中 provider message 发不出去，所以先写配置，等连上后再补一次重载（`afterConnect`）。
    func reloadTunnelIfRunning(_ t: any TunnelPort) async {
        let st = await t.currentStatus()
        do {
            try await writeTunnelConfig(to: t.configURL, controllerSocket: t.controllerSocketPath)
        } catch {
            return   // 写失败：扩展保持旧配置继续工作，核心里的改动已落盘
        }
        switch st {
        case .connected: try? await t.reloadConfig()
        case .connecting: afterConnect(t) { try? await t.reloadConfig() }
        default: break
        }
    }

    /// 连接中时排队一个动作：每 0.5 s 查一次，连上就执行；离开 connecting（失败/断开）或 30 s 后放弃。
    func afterConnect(_ t: any TunnelPort, _ action: @escaping @Sendable () async -> Void) {
        Task.detached(priority: .utility) {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                switch await t.currentStatus() {
                case .connected: await action(); return
                case .connecting: continue
                default: return
                }
            }
        }
    }

    // MARK: 流量

    func liveTraffic(_ t: any TunnelPort) -> AsyncStream<TrafficSample> {
        trafficBroadcast.subscribe { [weak self] in
            guard let self else { return AsyncStream { $0.finish() } }
            return self.poll(every: 1) { [weak self] in
                guard let self, let r = await t.rate() else { return nil }
                let s = TrafficSample(at: self.now(), upBps: r.up, downBps: r.down)
                self.remember(s)
                return s
            }
        }
    }

    // MARK: 日志（契约 §8：扩展内环形缓冲 500 条，1 Hz 增量拉取）

    private struct LogBatch: Decodable {
        struct Line: Decodable { let seq: Int64; let level: String; let msg: String; let at: Int64 }
        let seq: Int64
        let lines: [Line]
    }

    func liveLogs(_ t: any TunnelPort, minLevel: LogLevel) -> AsyncStream<LogLine> {
        AsyncStream(bufferingPolicy: .bufferingNewest(500)) { k in
            let task = Task {
                var since: Int64 = 0
                while !Task.isCancelled {
                    if let json = await t.logs(since: since, minLevel: minLevel.rawValue, limit: 200),
                       let b = try? JSONDecoder().decode(LogBatch.self, from: Data(json.utf8)) {
                        // 扩展重启后序号回到更小值：从头再拉
                        since = b.seq < since ? 0 : b.seq
                        for l in b.lines {
                            k.yield(LogLine(at: l.at, level: LogLevel(rawValue: l.level) ?? .info, message: l.msg))
                        }
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                k.finish()
            }
            k.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 策略组

    func livePolicyGroups(_ t: any TunnelPort) -> AsyncStream<[ZephyrKit.PolicyGroup]> {
        let path = t.controllerSocketPath
        return poll(every: 3) { [weak self] in
            guard let self else { return nil }
            let groups = (try? await self.mihomo(path) { try $0.policyGroups() }) ?? []
            return groups.map(CoreEngine.domain)
        }
    }

    func liveGroupMembers(_ t: any TunnelPort, group: String, offset: Int32, limit: Int32) async throws -> ZephyrKit.NodePage {
        let path = t.controllerSocketPath
        let (members, total) = try await mihomo(path) { c -> ([GroupMember], Int64) in
            let ms = try c.groupMembers(group: group, offset: UInt32(max(offset, 0)), limit: UInt32(max(limit, 0)))
            let count = try c.policyGroups().first { $0.name == group }.map { Int64($0.memberCount) }
            return (ms, count ?? Int64(offset) + Int64(ms.count))
        }
        let rows = members.map { m -> NodeSummary in
            let id = CoreEngine.memberId(group: group, name: m.name)
            return NodeSummary(id: id, name: m.name, region: "", protocol: m.proxyType, latencyMs: m.latencyMs)
        }
        rememberMembers(rows.map { ($0.id, $0.name) })
        return ZephyrKit.NodePage(rows: rows, offset: Int64(offset), total: total)
    }

    func liveSelect(_ t: any TunnelPort, group: String, nodeId: NodeId) async throws {
        guard let name = memberName(nodeId) else {
            throw ZephyrError(code: .nodeNotFound, message: "member \(nodeId) not loaded in \(group)")
        }
        try await mihomo(t.controllerSocketPath) { try $0.selectInGroup(group: group, member: name) }
    }

    func liveTestGroup(_ t: any TunnelPort, group: String) async throws {
        _ = try await mihomo(t.controllerSocketPath) {
            try $0.testGroup(group: group, url: "https://www.gstatic.com/generate_204", timeoutMs: 5000)
        }
    }

    // MARK: 连接列表

    func liveConnections(_ t: any TunnelPort) -> AsyncStream<[ZephyrKit.ConnectionInfo]> {
        let path = t.controllerSocketPath
        return poll(every: 1) { [weak self] in
            guard let self else { return nil }
            let list = (try? await self.mihomo(path) { try $0.activeConnections(limit: 500) }) ?? []
            return list.map {
                ZephyrKit.ConnectionInfo(id: $0.id, host: $0.host, app: $0.app, scene: $0.scene, node: $0.node,
                                         upBytes: $0.upBytes, downBytes: $0.downBytes, startedAt: $0.startedAt)
            }
        }
    }

    func liveClose(_ t: any TunnelPort, id: String?) async throws {
        try await mihomo(t.controllerSocketPath) { c in
            if let id { try c.closeConnection(id: id) } else { try c.closeAllConnections() }
        }
    }

    // MARK: 映射

    static func domain(_ g: PolicyGroup) -> ZephyrKit.PolicyGroup {
        let type: ZephyrKit.GroupType = switch g.groupType {
        case .select: .select
        case .urlTest: .urlTest
        case .fallback: .fallback
        case .loadBalance: .loadBalance
        case .relay: .relay
        }
        return ZephyrKit.PolicyGroup(name: g.name, type: type, selected: g.selected, memberCount: g.memberCount, testedAt: g.testedAt)
    }

    /// 组成员的稳定 id（FNV-1a 64，组名 + 成员名）：同一成员跨刷新不变，供列表 diff 与 selectInGroup 回查。
    static func memberId(group: String, name: String) -> NodeId {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in group.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        h = (h ^ 0x1f) &* 0x100_0000_01b3
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    // MARK: 基础设施

    /// 在后台并发队列上用一个新的 MihomoClient 执行阻塞 REST 调用。
    func mihomo<T: Sendable>(_ socketPath: String, _ body: @escaping @Sendable (MihomoClient) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<T, Error>) in
            liveQueue.async {
                do { k.resume(returning: try body(MihomoClient(socketPath: socketPath))) } catch let e as MobileError {
                    k.resume(throwing: CoreEngine.map(e, notFound: .nodeNotFound))
                } catch {
                    k.resume(throwing: error)
                }
            }
        }
    }

    /// 周期拉取；`fetch` 返回 nil 表示本轮无数据（不 yield）。订阅方取消时停止。
    func poll<T: Sendable>(every seconds: Double, _ fetch: @escaping @Sendable () async -> T?) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { k in
            let task = Task {
                while !Task.isCancelled {
                    if let v = await fetch() { k.yield(v) }
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }
                k.finish()
            }
            k.onTermination = { _ in task.cancel() }
        }
    }
}

let liveQueue = DispatchQueue(label: "app.zephyr.core.live", qos: .userInitiated, attributes: .concurrent)

/// 限时等待：`op` 在 `seconds` 内没有结果返回 nil，调用方不会被挂起。
/// 用两个非结构化任务竞速 + 一次性 continuation：任务组会等所有子任务结束，op 不响应取消时超时形同虚设
/// （REVIEW-Q2 X-P1 withDeadline）。超时后 op 被取消，其迟到的结果直接丢弃。
public func withDeadline<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
        let once = DeadlineOnce<T>(cont)
        let work = Task {
            let v = await op()
            once.finish(v)
        }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            if once.finish(nil) { work.cancel() }
        }
        once.onFinish { timer.cancel() }
    }
}

/// 只恢复一次的 continuation 包装。
private final class DeadlineOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T?, Never>?
    private var cleanup: (@Sendable () -> Void)?
    private var done = false

    init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }

    @discardableResult
    func finish(_ value: T?) -> Bool {
        lock.lock()
        if done { lock.unlock(); return false }
        done = true
        let c = cont; cont = nil
        let f = cleanup; cleanup = nil
        lock.unlock()
        c?.resume(returning: value)
        f?()
        return true
    }

    func onFinish(_ f: @escaping @Sendable () -> Void) {
        lock.lock()
        if done { lock.unlock(); f(); return }
        cleanup = f
        lock.unlock()
    }
}

public extension TunnelPort {
    func currentStatus() async -> ConnectionStatus {
        await withDeadline(2) {
            var it = self.states().makeAsyncIterator()
            return await it.next()?.status
        } ?? .disconnected
    }
}

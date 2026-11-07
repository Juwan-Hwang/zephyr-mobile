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
}

extension CoreEngine {

    // MARK: 连接

    func liveConnect(_ t: any TunnelPort) async throws {
        try await writeTunnelConfig(to: t.configURL, controllerSocket: t.controllerSocketPath)
        try await t.start()
    }

    /// 隧道在跑时：重写配置并让扩展热重载；没在跑则什么都不做（下次连接时 liveConnect 会重写）。
    func isTunnelConnected(_ t: any TunnelPort) async -> Bool {
        var it = t.states().makeAsyncIterator()
        return await it.next()?.status == .connected
    }

    func reloadTunnelIfRunning(_ t: any TunnelPort) async {
        guard await isTunnelConnected(t) else { return }
        do {
            try await writeTunnelConfig(to: t.configURL, controllerSocket: t.controllerSocketPath)
            try await t.reloadConfig()
        } catch {
            // 热重载失败不影响订阅/场景本身已写入核心；扩展保持旧配置继续工作。
        }
    }

    // MARK: 流量

    func liveTraffic(_ t: any TunnelPort) -> AsyncStream<TrafficSample> {
        poll(every: 1) { [weak self] in
            guard let self, let r = await t.rate() else { return nil }
            let s = TrafficSample(at: self.now(), upBps: r.up, downBps: r.down)
            self.remember(s)
            return s
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

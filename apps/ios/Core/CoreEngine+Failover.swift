// 场景自动切换（契约 v0.2「场景自动切换」+ §14.y，REVIEW-Q2 X-P1-5 余项）。
//
// iOS 的 PacketTunnel 不链接核心（NE 内存上限），所以探测在 App 进程里做：AppModel 只在“前台且已连接”时订阅，每 60 s 一轮，
// 底层网络变化后立即一轮（契约 §16.a③）。计费网络下不跳过（§16.c：testOnWifiOnly 不管故障探测）。
// 每个已选节点的场景：在 mihomo 里测该场景的策略组，按组自己的 `selected` 成员判断是否可达（不依赖成员名映射），
// 把结果上报核心 reportSceneProbe，由核心按阈值 / 冷却决定是否在热备内切换；返回非空即需 selectInGroup（不重载、不断连）。
//   - 组内所有成员都不通：多半是探测地址本身被墙 / 本机断网，不算节点失败，不上报。
//   - 探测期间用户换了节点：结果属于旧节点，丢弃。
//   - selectInGroup 失败：把核心的选择撤回 previous，不报“已切换”。
// AI 场景：出口 IP 只能由用户确认后更改，从不上报计数、从不自动切换，只提示“出口无响应”，且同一次故障只提示一次。
// 与 Android probeScenes 同规则。

import Foundation
import ZephyrKit

/// 跨轮次的探测状态（AI 场景已提示过的故障）。
final class FailoverState: @unchecked Sendable {
    private let lock = NSLock()
    private var warned: Set<String> = []
    /// 返回 true 表示这是一次新的故障（应当提示）。
    func markFailed(_ sceneId: String) -> Bool { lock.lock(); defer { lock.unlock() }; return warned.insert(sceneId).inserted }
    func markOk(_ sceneId: String) { lock.lock(); warned.remove(sceneId); lock.unlock() }
}

extension CoreEngine {
    static let failoverProbeInterval: UInt64 = 60_000_000_000
    static let failoverProbeURL = "https://www.gstatic.com/generate_204"

    /// 每 60 s 一轮；底层网络变化（扩展去抖 2 s 并 closeAll 后经 `TunnelPort.networkChanges()` 通知）时立即再跑一轮（§16.a③）。
    /// 只在 AppModel 订阅时运行，即“前台且已连接”（§16.f E21）。
    /// 计费网络下**不**跳过：故障探测每场景每轮一个 generate_204，流量可忽略；testOnWifiOnly 只管自动测速（§16.c）。
    public func sceneFailovers() -> AsyncStream<SceneFailoverNotice> {
        guard let t = tunnel, core != nil else { return AsyncStream { $0.finish() } }
        return failoverBroadcast.subscribe { [weak self] in
            AsyncStream(bufferingPolicy: .bufferingNewest(8)) { k in
                // 两个来源合并成“该跑一轮了”；缓冲 1 个，探测中再来的触发合并为下一轮。
                let (ticks, tick) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                let timer = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: CoreEngine.failoverProbeInterval)
                        if Task.isCancelled { break }
                        tick.yield()
                    }
                }
                let network = Task {
                    for await _ in t.networkChanges() {
                        if Task.isCancelled { break }
                        tick.yield()
                    }
                }
                let task = Task {
                    for await _ in ticks {
                        guard !Task.isCancelled, let self else { break }
                        guard await self.isTunnelConnected(t) else { continue }
                        for notice in await self.probeScenesOnce(t) { k.yield(notice) }
                    }
                    k.finish()
                }
                k.onTermination = { _ in
                    timer.cancel(); network.cancel(); task.cancel()
                    tick.finish()
                }
            }
        }
    }

    /// 已选节点的场景（只取基本类型，不把 UniFFI 记录跨并发边界传递）。
    private func selectedScenes(_ c: MobileCore) async -> [(id: String, name: String, group: String, isAI: Bool, nodeId: UInt64)] {
        let clock = self.clock
        return (try? await run(.sceneNotFound) {
            try c.scenes(nowMillis: clock()).compactMap { s in
                s.selected.map { (id: s.id, name: s.name, group: s.group, isAI: s.kind == .ai, nodeId: $0.id) }
            }
        }) ?? []
    }

    /// 一轮探测；返回本轮需要告诉用户的事件。
    func probeScenesOnce(_ t: any TunnelPort) async -> [SceneFailoverNotice] {
        guard let c = await nodes() else { return [] }
        let clock = self.clock
        let scenes = await selectedScenes(c)
        guard !scenes.isEmpty else { return [] }
        let path = t.controllerSocketPath
        guard let groups = try? await mihomo(path, { try $0.policyGroups().map { (name: $0.name, selected: $0.selected) } }) else {
            return []   // mihomo 不通：本轮不上报，避免把控制面故障算成节点失败
        }
        var selectedByGroup: [String: String] = [:]
        for g in groups { if let sel = g.selected, selectedByGroup[g.name] == nil { selectedByGroup[g.name] = sel } }

        var out: [SceneFailoverNotice] = []
        for sc in scenes {
            guard !Task.isCancelled, let sel = selectedByGroup[sc.group] else { continue }
            let group = sc.group
            guard let tested = try? await mihomo(path, {
                try $0.testGroup(group: group, url: CoreEngine.failoverProbeURL, timeoutMs: 5000)
                    .map { (name: $0.name, ms: Int($0.latencyMs ?? 0)) }
            }) else { continue }
            // 全组都不通：探测本身不可用，不算节点失败。
            guard tested.contains(where: { $0.ms > 0 }) else { continue }
            let ok = (tested.first { $0.name == sel }?.ms ?? 0) > 0
            // 探测期间用户换了节点：这次结果不属于当前选择。
            guard let now = await selectedScenes(c).first(where: { $0.id == sc.id }), now.nodeId == sc.nodeId else { continue }

            if sc.isAI {
                if ok { failoverState.markOk(sc.id) }
                else if failoverState.markFailed(sc.id) { out.append(SceneFailoverNotice(sceneId: sc.id, sceneName: sc.name, failedNode: sel)) }
                continue
            }
            let sceneId = sc.id
            let hit: (failed: String, group: String, member: String, previous: UInt64?)?? = try? await run(.sceneNotFound) {
                try c.reportSceneProbe(sceneId: sceneId, success: ok, nowMillis: clock()).map {
                    (failed: $0.failed.name, group: $0.apply.group, member: $0.apply.member, previous: $0.apply.previous)
                }
            }
            guard let f = hit ?? nil else { continue }
            let g = f.group, m = f.member
            do {
                try await mihomo(path, { try $0.selectInGroup(group: g, member: m) })
            } catch {
                // mihomo 没切过去：撤回核心里的选择，避免 UI 显示一个并没有生效的节点。
                if let prev = f.previous {
                    _ = try? await run(.sceneNotFound) { try c.applySceneChange(sceneId: sceneId, nodeId: prev, nowMillis: clock()) }
                }
                continue
            }
            out.append(SceneFailoverNotice(sceneId: sc.id, sceneName: sc.name, failedNode: f.failed,
                                           switchedTo: m, previousNodeId: f.previous))
        }
        if out.contains(where: { $0.switchedTo != nil }) { await bumpScenes() }
        return out
    }
}

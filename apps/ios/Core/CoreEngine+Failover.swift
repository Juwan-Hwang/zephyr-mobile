// 场景自动切换（契约 v0.2「场景自动切换」+ §14.y，REVIEW-Q2 X-P1-5 余项）。
//
// iOS 的 PacketTunnel 不链接核心（NE 内存上限），所以探测在 App 进程里做：App 在前台且隧道已连接时，每 60 s 一轮。
// 每个已选节点的场景：在 mihomo 里测该场景的策略组，按组自己的 `selected` 成员判断是否可达（不依赖成员名映射），
// 把结果上报核心 reportSceneProbe，由核心按阈值 / 冷却决定是否在热备内切换；返回非空即需 selectInGroup（不重载、不断连）。
// AI 场景：出口 IP 只能由用户确认后更改，从不上报计数、从不自动切换，只提示“出口无响应”。与 Android probeScenes 同规则。

import Foundation
import ZephyrKit

extension CoreEngine {
    static let failoverProbeInterval: UInt64 = 60_000_000_000
    static let failoverProbeURL = "https://www.gstatic.com/generate_204"

    public func sceneFailovers() -> AsyncStream<SceneFailoverNotice> {
        guard let t = tunnel, core != nil else { return AsyncStream { $0.finish() } }
        return failoverBroadcast.subscribe { [weak self] in
            AsyncStream(bufferingPolicy: .bufferingNewest(8)) { k in
                let task = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: CoreEngine.failoverProbeInterval)
                        guard !Task.isCancelled, let self else { break }
                        guard await self.isTunnelConnected(t) else { continue }
                        for notice in await self.probeScenesOnce(t) { k.yield(notice) }
                    }
                    k.finish()
                }
                k.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// 一轮探测；返回本轮需要告诉用户的事件。
    func probeScenesOnce(_ t: any TunnelPort) async -> [SceneFailoverNotice] {
        guard let c = await nodes() else { return [] }
        let clock = self.clock
        // 只取需要的字段（基本类型），不把 UniFFI 记录跨并发边界传递。
        let scenes: [(id: String, name: String, group: String, isAI: Bool)] =
            (try? await run(.sceneNotFound) {
                try c.scenes(nowMillis: clock()).filter { $0.selected != nil }.map {
                    (id: $0.id, name: $0.name, group: $0.group, isAI: $0.kind == .ai)
                }
            }) ?? []
        guard !scenes.isEmpty else { return [] }
        let path = t.controllerSocketPath
        guard let groups = try? await mihomo(path, { try $0.policyGroups().map { (name: $0.name, selected: $0.selected) } }) else {
            return []   // mihomo 不通：本轮不上报，避免把控制面故障算成节点失败
        }
        var selectedByGroup: [String: String] = [:]
        for g in groups { if let sel = g.selected, selectedByGroup[g.name] == nil { selectedByGroup[g.name] = sel } }

        var out: [SceneFailoverNotice] = []
        for sc in scenes {
            guard let sel = selectedByGroup[sc.group] else { continue }
            let group = sc.group
            guard let tested = try? await mihomo(path, {
                try $0.testGroup(group: group, url: CoreEngine.failoverProbeURL, timeoutMs: 5000)
                    .map { (name: $0.name, ms: $0.latencyMs) }
            }) else { continue }
            let ok = (tested.first { $0.name == sel }?.ms ?? 0) > 0
            if sc.isAI {
                if !ok { out.append(SceneFailoverNotice(sceneId: sc.id, sceneName: sc.name, failedNode: sel)) }
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
            _ = try? await mihomo(path, { try $0.selectInGroup(group: g, member: m) })
            out.append(SceneFailoverNotice(sceneId: sc.id, sceneName: sc.name, failedNode: f.failed,
                                           switchedTo: m, previousNodeId: f.previous))
        }
        if out.contains(where: { $0.switchedTo != nil }) { await bumpScenes() }
        return out
    }
}

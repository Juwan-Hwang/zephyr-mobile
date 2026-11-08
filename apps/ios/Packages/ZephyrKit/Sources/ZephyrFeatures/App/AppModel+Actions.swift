// AppModel 的写操作。全部 async、在主线程调用；错误写入 lastError，可撤销的操作给出撤销吐司（ZToastItem）。

import Foundation
import ZephyrDesign
import ZephyrKit

extension AppModel {

    // MARK: 连接

    /// 首页开关。连接前先执行 `beforeConnect`（App 层在这里启动 NEPacketTunnel / 请求 VPN 授权）。
    public func toggleConnection() async {
        if isOn { await disconnect() } else { await connect() }
    }

    public func connect() async {
        do {
            try await beforeConnect?()
            try await engine.connect()
        } catch { report(error) }
    }

    public func disconnect() async {
        do { try await engine.disconnect() } catch { report(error) }
    }

    public func setMode(_ mode: ProxyMode) async {
        guard mode != connection.mode else { return }
        let old = connection.mode
        connection.mode = mode          // 乐观更新，流随后确认
        do { try await engine.setMode(mode: mode) } catch { connection.mode = old; report(error) }
    }

    /// 全局模式"更换节点"。返回实际出口变化，并给出可撤销提示。
    @discardableResult
    public func setGlobalNode(_ node: NodeSummary) async -> ExitChange? {
        let previous = globalNode
        do {
            let change = try await engine.setGlobalNode(id: node.id)
            globalNode = node
            showUndo("已切换至\(node.name)") { [weak self] in
                guard let self, let previous else { return }
                _ = try? await self.engine.setGlobalNode(id: previous.id)
                self.globalNode = previous
            }
            return change
        } catch { report(error); return nil }
    }

    /// 全局模式"更换节点"的候选：合并各场景候选池，去重、按延迟升序、排除当前出口。
    /// 契约 v0 没有"全局候选"接口，暂用场景候选拼出（见 NOTES-H.md）。
    public func globalAlternatives() async -> [NodeSummary] {
        var seen = Set<NodeId>()
        var all: [NodeSummary] = []
        for s in scenes where s.source != .subscriptionGroup {
            guard let c = try? await engine.sceneCandidates(sceneId: s.id, region: nil) else { continue }
            for n in c where seen.insert(n.id).inserted { all.append(n) }
        }
        let current = connection.globalNodeId
        return all
            .filter { $0.id != current && ($0.latencyMs ?? 0) >= 0 }
            .sorted { ($0.latencyMs ?? .max) < ($1.latencyMs ?? .max) }
    }

    // MARK: 场景：左右滑动切换地区（原型 05）

    /// 拉取场景候选并按地区折叠：每个地区只留延迟最低的一个，地区按其最低延迟排序。
    public func loadRegionChoices(sceneId: String) async {
        guard let scene = scene(id: sceneId) else { return }
        do {
            let all = try await engine.sceneCandidates(sceneId: sceneId, region: nil)
            var seen = Set<String>()
            var picks: [NodeSummary] = []
            for n in all where !seen.contains(n.region) { seen.insert(n.region); picks.append(n) }
            if !seen.contains(scene.selected.region) { picks.append(scene.selected) }
            // 当前地区用当前节点，避免"滑回原位"时换了同地区的另一台。
            if let i = picks.firstIndex(where: { $0.region == scene.selected.region }) { picks[i] = scene.selected }
            regionChoices[sceneId] = picks
        } catch { report(error) }
    }

    /// 场景候选（场景详情列表）。按延迟排序，最多 50。
    public func sceneCandidates(_ sceneId: String, region: String? = nil) async -> [NodeSummary] {
        do { return try await engine.sceneCandidates(sceneId: sceneId, region: region) }
        catch { report(error); return [] }
    }

    /// 松手停在另一个地区：向引擎要出口变化预览，展示确认卡。
    public func beginSceneChange(sceneId: String, to node: NodeSummary) async {
        guard let scene = scene(id: sceneId), node.id != scene.selected.id else { pendingChange = nil; return }
        pendingChange = PendingSceneChange(sceneId: sceneId, from: scene.selected, to: node, exit: nil)
        do {
            let exit = try await engine.previewSceneChange(sceneId: sceneId, nodeId: node.id)
            if pendingChange?.to.id == node.id { pendingChange?.exit = exit }
        } catch { pendingChange = nil; report(error) }
    }

    public func cancelPendingChange() { pendingChange = nil }

    /// 确认卡"更改"。
    public func confirmPendingChange() async {
        guard let p = pendingChange else { return }
        pendingChange = nil
        await applySceneChange(sceneId: p.sceneId, from: p.from, to: p.to)
    }

    /// 场景详情候选列表点选（原型 06），或确认卡确认后调用。带撤销。
    public func applySceneChange(sceneId: String, from: NodeSummary, to: NodeSummary) async {
        do {
            try await engine.applySceneChange(sceneId: sceneId, nodeId: to.id)
            showUndo("已切换至\(to.name)") { [weak self] in
                guard let self else { return }
                do { try await self.engine.applySceneChange(sceneId: sceneId, nodeId: from.id) } catch { self.report(error) }
            }
        } catch { report(error) }
    }

    /// 重新检测场景池（首页"检测中"变体）。
    public func retest(sceneId: String) async {
        retesting.insert(sceneId)
        defer { retesting.remove(sceneId) }
        do {
            let s = try await engine.retestScene(sceneId: sceneId)
            if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s }
        } catch { report(error) }
    }

    /// 场景节点来源：订阅分组 ↔ Zephyr 优选（契约 §14.z setSceneSource）。场景流会随核心更新回写。
    public func setSceneSource(sceneId: String, source: SceneSource) async {
        guard let current = scene(id: sceneId)?.source, current != source else { return }
        do { try await engine.setSceneSource(sceneId: sceneId, source: source) } catch { report(error) }
    }

    /// 域名路由覆写（契约 §13 overrideHost）：直连 / 指定场景 / 清除（.unchanged）。成功后给可撤销吐司。
    @discardableResult
    public func overrideHost(_ host: String, target: TraceTarget, sceneId: String?, persistent: Bool) async -> Bool {
        do {
            try await engine.overrideHost(host: host, target: target, sceneId: sceneId, persistent: persistent)
            switch target {
            case .unchanged:
                showUndo("已清除 \(host) 的路由覆写")
            case .direct:
                showUndo("\(host) 已改为直连") { [weak self] in
                    guard let self else { return }
                    do { try await self.engine.overrideHost(host: host, target: .unchanged, sceneId: nil, persistent: persistent) }
                    catch { self.report(error) }
                }
            case .scene:
                let name = sceneId.flatMap { scene(id: $0)?.name } ?? "场景"
                showUndo("\(host) 已改走 \(name)") { [weak self] in
                    guard let self else { return }
                    do { try await self.engine.overrideHost(host: host, target: .unchanged, sceneId: nil, persistent: persistent) }
                    catch { self.report(error) }
                }
            }
            return true
        } catch { report(error); return false }
    }

    // MARK: 撤销提示

    /// 显示带"撤销"的吐司（停留 ZTokens.Motion.undoWindow）。`undo` 为 nil 时只显示文字。
    /// ZToastItem 的 action 是同步闭包，这里包一层主线程 Task 再执行异步撤销。
    public func showUndo(_ message: String, undo: (@MainActor @Sendable () async -> Void)? = nil) {
        guard let undo else { toast = ZToastItem(message); return }
        toast = ZToastItem(message, actionTitle: "撤销") {
            Task { @MainActor in await undo() }
        }
    }

    public func dismissToast() { toast = nil }

    // MARK: 错误

    func report(_ error: Error) {
        if let z = error as? ZephyrError {
            if z.code != .cancelled { lastError = z }
        } else if !(error is CancellationError) {
            lastError = ZephyrError(code: .internal, message: String(describing: error))
        }
    }
}

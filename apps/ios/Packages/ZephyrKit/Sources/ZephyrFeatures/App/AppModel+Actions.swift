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
            showUndo(ZL.s("已切换至%@", node.name)) { [weak self] in
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

    /// 场景详情候选列表点选（原型 06），或确认卡确认后调用。带撤销。`message` 为 nil 时用“已切换至<节点>”。
    @discardableResult
    public func applySceneChange(sceneId: String, from: NodeSummary, to: NodeSummary, message: String? = nil) async -> Bool {
        do {
            try await engine.applySceneChange(sceneId: sceneId, nodeId: to.id)
            showUndo(message ?? ZL.s("已切换至%@", to.name)) { [weak self] in
                guard let self else { return }
                do { try await self.engine.applySceneChange(sceneId: sceneId, nodeId: from.id) } catch { self.report(error) }
            }
            return true
        } catch { report(error); return false }
    }

    /// 契约 §16.d “Gemini 走日本”：只钉该服务的例外，场景 selected 与其他服务不变。
    /// 吐司“<服务> 现使用<节点>”；撤销恢复原例外节点（原来没有则删除例外）。
    @discardableResult
    public func applySceneException(sceneId: String, appId: String, service: String, node: NodeSummary,
                                    previous: NodeSummary?) async -> Bool {
        do {
            try await engine.setSceneException(sceneId: sceneId, appId: appId, nodeId: node.id)
            let restore = previous?.id
            showUndo(ZL.s("%@ 现使用%@", service, node.name)) { [weak self] in
                guard let self else { return }
                do { try await self.engine.setSceneException(sceneId: sceneId, appId: appId, nodeId: restore) }
                catch { self.report(error) }
            }
            return true
        } catch { report(error); return false }
    }

    /// 重新检测场景池（首页"检测中"变体）：服务探测与节点扫描（契约 §15.d）并行，
    /// 扫描进度写进 `scan`（首页“正在检测 138/512”+ 行内进度条），两者都结束才退出“检测中”。
    public func retest(sceneId: String) async {
        retesting.insert(sceneId)
        defer { retesting.remove(sceneId) }
        let engine = self.engine
        let scanning = scan == nil
        // 契约 §15.e：按场景当前节点地区扫（未选节点为空串 = 全库）。
        let query = scenes.first(where: { $0.id == sceneId })?.scanQuery ?? ""
        let scanTask: Task<Void, Never>? = scanning ? Task { [weak self] in
            for await p in engine.scanLatency(query: query) { self?.scan = p }
            self?.scan = nil
        } : nil
        do {
            let s = try await engine.retestScene(sceneId: sceneId)
            if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s }
        } catch { report(error) }
        await scanTask?.value
    }

    /// 场景节点来源：订阅分组 ↔ Zephyr 优选（契约 §14.z setSceneSource）。场景流会随核心更新回写。
    /// 契约 §15.h：设置 / 清除场景节点过滤（“视频只用 4K 节点”）。核心不切当前节点；`switchTo` 只在用户已在
    /// 预览卡上看过出口 IP 变化并点“应用”时传入（§14.y，不自动切换）。成功给可撤销吐司，失败走横幅。
    @discardableResult
    public func applySceneNodeFilter(sceneId: String, filter: SceneNodeFilter?, switchTo node: NodeSummary? = nil) async -> Bool {
        guard let before = scene(id: sceneId) else { return false }
        do { try await engine.setSceneNodeFilter(sceneId: sceneId, filter: filter) } catch { report(error); return false }
        var switched = false
        if let node, node.id != before.selected.id {
            do { try await engine.applySceneChange(sceneId: sceneId, nodeId: node.id); switched = true } catch { report(error) }
        }
        let message: String
        if filter == nil {
            message = ZL.s("%@已取消仅 4K 节点", before.name)
        } else if switched, let node {
            message = ZL.s("%1$@仅使用 4K 节点，已切换至%2$@", before.name, node.name)
        } else {
            message = ZL.s("%@仅使用 4K 节点", before.name)
        }
        let didSwitch = switched
        showUndo(message) { [weak self] in
            guard let self else { return }
            do {
                // 先恢复过滤（清除总是成功），再换回原节点，避免旧节点被过滤挡住。
                try await self.engine.setSceneNodeFilter(sceneId: sceneId, filter: before.nodeFilter)
                if didSwitch { try await self.engine.applySceneChange(sceneId: sceneId, nodeId: before.selected.id) }
            } catch { self.report(error) }
        }
        return true
    }

    /// 引导第 2 步“简单 / 优选”（审计 #207 U3，对齐 Android `applyOnboardingMode`）：简单 = 所有场景用订阅提供的分组
    /// （subscription_group），优选 = Zephyr 优选（auto）。首次安装尚未用过任何出口，不算需要确认的出口变更（§14.y）。
    /// 场景流还没落地时最多等 2 秒取首帧；单个场景失败不打断其余场景，也不弹横幅（与 Android runCatching 一致）。
    public func applyOnboardingChoice(_ choice: OnboardingChoice) async {
        let source = choice.sceneSource
        var list = scenes
        if list.isEmpty { list = await firstScenes(timeout: 2) }
        for s in list where s.source != source {
            try? await engine.setSceneSource(sceneId: s.id, source: source)
        }
    }

    /// 场景流的首帧，超时返回空。
    private func firstScenes(timeout seconds: Double) async -> [ZephyrKit.Scene] {
        let engine = self.engine
        return await withTaskGroup(of: [ZephyrKit.Scene]?.self) { group in
            group.addTask {
                for await list in engine.scenes() { return list }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    public func setSceneSource(sceneId: String, source: SceneSource) async {
        guard let current = scene(id: sceneId)?.source, current != source else { return }
        do { try await engine.setSceneSource(sceneId: sceneId, source: source) } catch { report(error) }
    }

    /// 域名路由覆写（契约 §13 overrideHost）：直连 / 指定场景 / 清除（.unchanged）。成功后给可撤销吐司。
    @discardableResult
    /// `message` 覆盖默认吐司文案（指令“GitHub 直连”用“GitHub 现为直连”，契约 §16.d）。
    public func overrideHost(_ host: String, target: TraceTarget, sceneId: String?, persistent: Bool,
                             message: String? = nil) async -> Bool {
        do {
            try await engine.overrideHost(host: host, target: target, sceneId: sceneId, persistent: persistent)
            switch target {
            case .unchanged:
                showUndo(ZL.s("已清除 %@ 的路由覆写", host))
            case .direct:
                showUndo(message ?? ZL.s("%@ 已改为直连", host)) { [weak self] in
                    guard let self else { return }
                    do { try await self.engine.overrideHost(host: host, target: .unchanged, sceneId: nil, persistent: persistent) }
                    catch { self.report(error) }
                }
            case .scene:
                let name = sceneId.flatMap { scene(id: $0)?.name } ?? ZL.tr("场景")
                showUndo(ZL.s("%@ 已改走 %@", host, name)) { [weak self] in
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
        toast = ZToastItem(message, actionTitle: ZL.tr("撤销")) {
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

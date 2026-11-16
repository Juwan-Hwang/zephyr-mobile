// 指令层的状态：输入 → 本地 token 化（即时）+ 引擎 commandSuggestions（80ms 防抖）→ 主预览（switch_node 时
// 向引擎要出口变化）→ "应用"。
//
// 契约 §9 的 switch_node payload 只有节点 id（Mock：String(nodeId)）。落到哪个场景按以下顺序决定：
//   1. payload 若为 "sceneId:nodeId" 直接用（建议 A 在契约里固定这个格式，见 NOTES-H.md）
//   2. 输入里识别出的服务所属场景（Gemini → ai）
//   3. 建议标题以场景名开头（"AI 切到东京 03"）
//   4. 候选池包含该节点的第一个场景
//   5. 全局模式下 → setGlobalNode

import Foundation
import Observation
import ZephyrKit

@MainActor
@Observable
final class CommandModel {
    var input = "" { didSet { if input != oldValue { inputChanged() } } }
    private(set) var parse = CommandParse(tokens: [])
    private(set) var suggestions: [CommandSuggestion] = []
    /// 主预览：第一个 switch_node 建议的落点与出口变化。
    private(set) var preview: Preview?
    private(set) var isApplying = false
    /// 契约 §15.h：输入含“4K”操作时的场景节点过滤预览（取代 switch_node 主预览）。
    private(set) var filterPreview: FilterPreview?

    struct FilterPreview: Equatable {
        var sceneId: String
        var sceneName: String
        /// 场景已是“仅 4K 节点”：卡片改为“取消”。
        var active: Bool
        var result: NodeFilterPreview
        /// 当前地区根本没有 4K 节点时禁用（契约 §15.h poolMatching == 0）；已开启时总能取消。
        var canApply: Bool { active || result.poolMatching > 0 }
    }

    /// 回车 / “应用”是否有可执行的主预览。
    var hasPrimary: Bool { filterPreview?.canApply ?? (preview?.node != nil) }

    struct Preview: Equatable {
        var suggestion: CommandSuggestion
        var sceneId: String?
        var node: NodeSummary?
        var exit: ExitChange?
        var candidateCount: Int?
    }

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    func start(prefill: String) {
        input = prefill
        if prefill.isEmpty { inputChanged() }
    }

    private func inputChanged() {
        parse = CommandTokenizer.parse(input)
        searchTask?.cancel()
        let text = input
        searchTask = Task { [weak self] in
            if !text.isEmpty { try? await Task.sleep(nanoseconds: 80_000_000) }
            guard let self, !Task.isCancelled else { return }
            let list = await self.app.engine.commandSuggestions(input: text)
            guard !Task.isCancelled, self.input == text else { return }
            self.suggestions = list
            await self.buildPreview(text: text)
        }
    }

    private func buildPreview(text: String) async {
        if let f = await buildFilterPreview(text: text) {
            guard input == text else { return }
            filterPreview = f; preview = nil; return
        }
        guard input == text else { return }
        filterPreview = nil
        guard !text.isEmpty, let s = suggestions.first(where: { $0.kind == .switchNode }) else { preview = nil; return }
        var p = Preview(suggestion: s)
        guard let (sceneHint, nodeId) = Self.splitPayload(s.payload) else { preview = p; return }
        let sceneId = await resolveScene(hint: sceneHint, nodeId: nodeId, title: s.title)
        p.sceneId = sceneId
        if let sceneId {
            let pool = await quietCandidates(sceneId, region: parse.regionCode)
            p.candidateCount = parse.regionCode == nil ? nil : pool.count
            p.node = pool.first { $0.id == nodeId }
            p.exit = try? await app.engine.previewSceneChange(sceneId: sceneId, nodeId: nodeId)
        }
        if p.node == nil { p.node = try? await app.engine.node(id: nodeId).summary }
        guard input == text else { return }
        preview = p
    }

    /// “视频只用 4K 节点”：识别出 4K 操作时按服务所属场景（默认视频）向引擎要过滤预览。
    /// 预览失败（场景不存在 / 引擎不支持）只当作没有过滤预览，回到普通建议，不弹横幅。
    private func buildFilterPreview(text: String) async -> FilterPreview? {
        guard !text.isEmpty, parse.wantsUHD else { return nil }
        let sceneId = parse.sceneId ?? "video"
        guard let scene = app.scene(id: sceneId),
              let r = try? await app.engine.previewSceneNodeFilter(sceneId: sceneId, filter: .uhd) else { return nil }
        return FilterPreview(sceneId: sceneId, sceneName: scene.displayName, active: scene.nodeFilter == .uhd, result: r)
    }

    private func resolveScene(hint: String?, nodeId: NodeId, title: String) async -> String? {
        if let hint, app.scene(id: hint) != nil { return hint }
        if let sid = parse.sceneId, app.scene(id: sid) != nil { return sid }
        if let s = app.scenes.first(where: { title.hasPrefix($0.name + " ") }) { return s.id }
        if app.connection.mode == .global { return nil }
        for s in app.scenes where s.source != .subscriptionGroup {
            if await quietCandidates(s.id).contains(where: { $0.id == nodeId }) { return s.id }
        }
        return nil
    }

    /// 指令层随输入预取候选：失败只当作没有候选，不写 lastError 弹横幅（REVIEW-Q1 H-P2-18）。
    private func quietCandidates(_ sceneId: String, region: String? = nil) async -> [NodeSummary] {
        (try? await app.engine.sceneCandidates(sceneId: sceneId, region: region)) ?? []
    }

    /// "123" → (nil, 123)；"ai:123" → ("ai", 123)
    static func splitPayload(_ payload: String) -> (String?, NodeId)? {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let id = NodeId(parts[1]) { return (parts[0], id) }
        if let id = NodeId(payload) { return (nil, id) }
        return nil
    }

    // MARK: 执行

    /// 应用主预览。返回 true 表示已执行（调用方收起指令层）。
    func applyPreview() async -> Bool {
        if let f = filterPreview { return await applyFilter(f) }
        guard let p = preview, let node = p.node else { return false }
        isApplying = true
        defer { isApplying = false }
        if let sid = p.sceneId, let scene = app.scene(id: sid) {
            await app.applySceneChange(sceneId: sid, from: scene.selected, to: node)
            if let who = parse.serviceName { app.toast?.message = ZL.s("%@ 现使用%@", who, node.name) }
        } else {
            await app.setGlobalNode(node)
        }
        return true
    }

    /// 契约 §15.h：开启时若当前节点不满足，用户已在卡片上看到出口 IP 变化，点“应用”即确认换到 suggested。
    private func applyFilter(_ f: FilterPreview) async -> Bool {
        guard f.canApply else { return false }
        isApplying = true
        defer { isApplying = false }
        if f.active { return await app.applySceneNodeFilter(sceneId: f.sceneId, filter: nil) }
        let to = f.result.currentKept ? nil : f.result.suggested
        return await app.applySceneNodeFilter(sceneId: f.sceneId, filter: .uhd, switchTo: to)
    }

    /// 执行一条普通建议（列表行）。
    func run(_ s: CommandSuggestion) async {
        switch s.kind {
        case .switchNode:
            if preview?.suggestion == s { _ = await applyPreview(); return }
            guard let (hint, id) = Self.splitPayload(s.payload),
                  let node = try? await app.engine.node(id: id).summary else { return }
            if let sid = await resolveScene(hint: hint, nodeId: id, title: s.title), let scene = app.scene(id: sid) {
                await app.applySceneChange(sceneId: sid, from: scene.selected, to: node)
            } else {
                await app.setGlobalNode(node)
            }
        case .switchMode:
            if let m = ProxyMode(rawValue: s.payload) { await app.setMode(m) }
        case .openNodeQuery:
            app.push(.nodes(query: s.payload))
        case .testRule:
            app.push(.rules(query: s.payload))
        case .openPage:
            openPage(s.payload)
        case .toggleConnection:
            switch s.payload {
            case "connect": await app.connect()
            case "disconnect": await app.disconnect()
            default: await app.toggleConnection()
            }
        }
    }

    private func openPage(_ id: String) {
        switch id {
        case "nodes": app.push(.nodes(query: ""))
        case "rules": app.push(.rules(query: nil))
        case "subscriptions": app.push(.subscriptions)
        case "settings": app.push(.settings)
        case "today": app.present(.today)
        case "connections", "logs": app.present(.connections(traceID: nil))
        case "scenes": if let s = app.scenes.first { app.present(.scene(id: s.id)) }
        case "library": app.present(.library)
        default: app.closeCommand()
        }
    }
}

// 场景详情（原型 06，截图 scene.png）：
//   AI                                   完成
//   9 个可用节点
//   检测自 … 个候选 · 2 小时前检测
//   [订阅分组 | Zephyr 优选]
//   漏斗
//   候选列表（点选切换，触感）
//   例外 / 检测频率 / 重新检测
//
// 契约 v0 只有 sceneCandidates（≤ 50）与 Scene.available；"检测自 2 个订阅中的 512 个节点"和
// 按服务的漏斗需要契约补充（见 NOTES-H.md），这里用候选数据推出能确定的三级漏斗。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct SceneSheet: View {
    let sceneId: String
    @Environment(AppModel.self) private var model
    @State private var candidates: [NodeSummary] = []
    @State private var loaded = false
    @State private var selecting: NodeId?

    var body: some View {
        if let scene = model.scene(id: sceneId) {
            content(scene)
        } else {
            ZSheet("场景") {
                ZEmptyState("场景已不存在", systemImage: "square.stack.3d.up.slash")
                    .padding(.top, ZTokens.Space.n8)
            }
        }
    }

    private func content(_ scene: Scene) -> some View {
        // D 的 ZSheet：抓手 + 标题 + "完成"（dismiss）+ 滚动正文。
        ZSheet(verbatim: scene.name) {
            VStack(alignment: .leading, spacing: 0) {
                ZBigNumber("\(scene.available)", unit: "个可用节点", size: .hero)
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n5)
                Text(verbatim: lede(scene))
                    .zType(.footnote).foregroundStyle(ZColor.t3)
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n3)

                ZSegmented([ZSegment(SceneSourceChoice.group, title: "订阅分组"),
                            ZSegment(SceneSourceChoice.pick, title: "Zephyr 优选")],
                           selection: Binding(
                               get: { scene.source == .subscriptionGroup ? .group : .pick },
                               set: { choice in
                                   let target: SceneSource = choice == .group ? .subscriptionGroup : .auto
                                   Task { await model.setSceneSource(sceneId: scene.id, source: target) }
                               }),
                           label: "节点来源")
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n6)

                if scene.source != .subscriptionGroup, loaded {
                    SceneFunnel(steps: funnel(scene))
                        .padding(.horizontal, HMetrics.homeInset)
                        .padding(.top, ZTokens.Space.n6)
                }

                candidateList(scene)
                    .padding(.top, ZTokens.Space.n6)

                detailList(scene)
                    .padding(.top, ZTokens.Space.n6)

                Text("优选结果仅保存在 Zephyr 中，订阅配置保持原样。")
                    .zType(.caption).foregroundStyle(ZColor.t3)
                    .padding(.horizontal, HMetrics.homeInset + ZTokens.Space.n1)
                    .padding(.top, ZTokens.Space.n3)
                    .padding(.bottom, ZTokens.Space.n8)
            }
        }
        .task(id: scene.testedAt) {
            candidates = await model.sceneCandidates(sceneId)
            loaded = true
        }
        .sensoryFeedback(.selection, trigger: scene.selected.id)
    }

    // MARK: 区块

    private func candidateList(_ scene: Scene) -> some View {
        ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
            LazyVStack(spacing: 0) {
                if !loaded {
                    ForEach(0..<6, id: \.self) { i in
                        if i > 0 { ZDivider() }
                        SceneCandidateRow(node: NodeSummary(id: 0, name: "占位节点 00", region: "XX", protocol: ""),
                                          isSelected: false, pinnedFor: nil)
                            .redacted(reason: .placeholder)
                    }
                }
                ForEach(Array(candidates.enumerated()), id: \.element.id) { i, node in
                    if i > 0 { ZDivider() }
                    Button {
                        select(node, in: scene)
                    } label: {
                        SceneCandidateRow(node: node,
                                          isSelected: node.id == (selecting ?? scene.selected.id),
                                          pinnedFor: scene.exceptions.first { $0.node.id == node.id }?.app)
                    }
                    .buttonStyle(ZRowButtonStyle(haptic: .none))
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("候选节点"))
    }

    private func detailList(_ scene: Scene) -> some View {
        ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
            VStack(spacing: 0) {
                ForEach(Array(scene.exceptions.enumerated()), id: \.offset) { _, ex in
                    DetailRow(title: ex.app, value: ZL.s("%@（固定）", ex.node.name))
                    ZDivider()
                }
                DetailRow(title: ZL.tr("检测频率"), value: Self.retestFrequency(model.settings))
                ZDivider()
                Button {
                    Task { await model.retest(sceneId: scene.id) }
                } label: {
                    HStack {
                        Text(verbatim: ZL.tr(model.retesting.contains(scene.id) ? "检测中…" : "重新检测"))
                            .zType(.body).foregroundStyle(ZAccentStyle())
                        Spacer()
                        if model.retesting.contains(scene.id) { ProgressView() }
                    }
                    .padding(.vertical, ZTokens.Space.n4)
                    .padding(.horizontal, ZTokens.Space.n5)
                }
                .buttonStyle(ZRowButtonStyle())
                .disabled(model.retesting.contains(scene.id))
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
    }

    // MARK: 逻辑

    private func select(_ node: NodeSummary, in scene: Scene) {
        guard node.id != scene.selected.id else { return }
        selecting = node.id
        Task {
            await model.applySceneChange(sceneId: scene.id, from: scene.selected, to: node)
            selecting = nil
        }
    }

    private func lede(_ scene: Scene) -> String {
        var parts: [String] = []
        if loaded, !candidates.isEmpty { parts.append(ZL.f("检测自 %lld 个候选节点", Int64(candidates.count))) }
        if let t = scene.testedAt { parts.append(ZL.s("%@检测", ZFormat.relative(t, now: model.now()))) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    /// 由候选推出的三级漏斗：候选 → 延迟低于 300 ms → 全部可访问（Scene.available）。
    private func funnel(_ scene: Scene) -> [FunnelStep] {
        let fast = candidates.filter { ($0.latencyMs ?? .max) >= 0 && ($0.latencyMs ?? .max) < 300 }.count
        return [FunnelStep(count: candidates.count, label: ZL.tr("全部候选")),
                FunnelStep(count: fast, label: ZL.tr("延迟低于 300 ms")),
                FunnelStep(count: Int(scene.available), label: ZL.tr("全部可访问"))]
    }
}

private enum SceneSourceChoice: Hashable { case group, pick }

@MainActor
private struct DetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Text(verbatim: title).zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
            Spacer(minLength: ZTokens.Space.n3)
            Text(verbatim: value).zType(.footnote).foregroundStyle(ZColor.t3)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, ZTokens.Space.n4)
        .padding(.horizontal, ZTokens.Space.n5)
        .accessibilityElement(children: .combine)
    }
}

#Preview("场景详情") {
    HPreview(model: .preview()) { SceneSheet(sceneId: "ai") }
}

#Preview("场景详情 · AX5") {
    HPreview(model: .preview()) { SceneSheet(sceneId: "ai") }
        .dynamicTypeSize(.accessibility5)
}

extension SceneSheet {
    /// “检测频率”行：结果超过延迟有效期（设置 › 延迟结果保留）后，回前台 / 后台刷新时自动重测（SceneRetestPlanner）。
    /// 24 小时仍说“每天”；其余按小时数，不再固定写“每天”（X-P1-5）。
    static func retestFrequency(_ settings: ZephyrKit.Settings?) -> String {
        let hours = Int64(max(1, settings?.latencyTtlHours ?? 24))
        let base = hours == 24 ? ZL.tr("每天") : ZL.f("每 %lld 小时", hours)
        return settings?.testOnWifiOnly == false ? base : ZL.s("%@（仅 Wi‑Fi）", base)
    }
}

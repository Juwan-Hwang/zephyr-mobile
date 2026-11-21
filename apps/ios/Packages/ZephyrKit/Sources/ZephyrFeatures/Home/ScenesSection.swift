// 首页"场景"区（原型 #scenesWrap / #globalWrap）。
//   规则 / 直连模式：场景卡（AI / 视频 / 其他），确认卡插在被切换的场景下方。
//   全局模式：全局模式卡（原型 12）。
//   未连接：卡片整体 55% 透明度（原型 `.off-state .rows .row{opacity:.55}`），仍可浏览与切换。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct ScenesSection: View {
    @Environment(\.zStaticRendering) private var still
    @Environment(AppModel.self) private var model
    /// 首页迷你漏斗（规范 §9.3，J-1）：每个场景行用各自的 sceneFunnel（契约 v0.7 §19.a）；缺项 = 没取到，行写「n 个可用」。
    @State private var funnels: [String: NodeFunnel] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "2 小时前检测"按分钟刷新；只有这一行随时间重算（REVIEW H-P2-7）。
            TimelineView(.everyMinute) { _ in
                ZSectionHeader("场景", trailing: model.connection.mode == .global ? nil : model.scenesTestedText)
            }
            .homeSectionInsets()
            if model.connection.mode == .global {
                GlobalModeCard()
            } else if model.scenes.isEmpty {
                ZCard { Text("添加订阅后，这里会显示 AI、视频等场景。").zType(.footnote).foregroundStyle(ZColor.t3) }
                    .padding(.horizontal, HMetrics.cardInset)
            } else {
                card
            }
        }
        .animation(still ? nil : ZMotion.slow, value: model.connection.mode)
    }

    private var card: some View {
        let firstScrubbable = model.scenes.first(where: Self.isScrubbable)?.id
        return ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
            VStack(spacing: 0) {
                ForEach(Array(model.scenes.enumerated()), id: \.element.id) { idx, scene in
                    if idx > 0 { ZDivider() }
                    let pending = model.pendingChange?.sceneId == scene.id ? model.pendingChange : nil
                    let coach = scene.id == firstScrubbable && model.isConnected
                    SceneRow(scene: scene,
                             scrubbable: Self.isScrubbable(scene),
                             showsCoach: coach,
                             isProbing: model.retesting.contains(scene.id),
                             pendingTarget: pending?.to,
                             funnel: funnels[scene.id])
                        // 提示气泡画在行下沿之外；抬高层级，盖住下一行之前的分隔线（原型 `.coach` 用 --s1 底，REVIEW H-P2-4）。
                        .zIndex(coach ? 1 : 0)
                    if let pending {
                        SceneChangeConfirm(change: pending, sceneName: scene.displayName)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(still ? nil : ZMotion.slow, value: model.pendingChange)
        }
        .opacity(model.isOn ? 1 : 0.55)
        .padding(.horizontal, HMetrics.cardInset)
        // 场景重测 / 换节点（地区变了）/ 改节点过滤 / 改「延迟结果保留」都重取；新鲜度同场景候选（latencyTtlHours），
        // 阈值 200 ms（latency.threshold-slow，契约 §19.a）。
        .task(id: funnelKey) { await loadFunnels() }
    }

    private var funnelKey: String {
        let scenes = model.scenes.map { "\($0.id):\($0.selected.region):\($0.testedAt ?? 0):\($0.nodeFilter?.rawValue ?? "")" }
        return scenes.joined(separator: ",") + "|\(SceneSheet.latencyTtlHours(model.settings))"
    }

    private func loadFunnels() async {
        let engine = model.engine
        let maxAge = SceneSheet.funnelMaxAgeMs(model.settings)
        let threshold = Int32(ZTokens.LatencyThreshold.slow)
        let ids = model.scenes.filter(Self.isScrubbable).map(\.id)
        var out: [String: NodeFunnel] = [:]
        await withTaskGroup(of: (String, NodeFunnel?).self) { group in
            for id in ids {
                group.addTask { (id, await engine.sceneFunnel(sceneId: id, maxAgeMs: maxAge, thresholdMs: threshold)) }
            }
            for await (id, f) in group { if let f { out[id] = f } }
        }
        guard !Task.isCancelled else { return }
        funnels = out
    }

    /// 订阅分组场景不参与 Zephyr 优选，不能左右滑动换地区。
    static func isScrubbable(_ s: Scene) -> Bool { s.source != .subscriptionGroup }
}

extension View {
    /// ZSectionHeader 自带左右 n2、上 n6；首页按原型 `.sec` 对齐到 22 / 上 30。
    func homeSectionInsets() -> some View {
        padding(.horizontal, HMetrics.homeInset - ZTokens.Space.n2)
            .padding(.top, HMetrics.sectionTop - ZTokens.Space.n6)
    }
}

#if DEBUG
#Preview("场景") {
    HPreview(model: .preview()) { ScrollView { ScenesSection() } }
}
#endif

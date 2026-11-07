// 首页场景行（原型 `.row[data-scene]`）。
//
// 左：场景名 + 状态（"9 个可用" / "订阅分组" / 检测中进度 / 无可用节点）
// 右：地区码 + 当前节点；第二行例外（🔒 Claude：US-Fixed-01）或备注（Netflix 完整片库）
// 交互：轻点 → 场景详情；左右滑动（每 42pt 一个地区）→ 逐格触感 + 地区码放大，松手后请求出口变化预览。
// VoiceOver：可调整（上下轻扫切换地区）+ 默认操作打开详情。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct SceneRow: View {
    let scene: Scene
    let scrubbable: Bool
    let showsCoach: Bool
    let isProbing: Bool
    /// 待确认切换的目标（确认卡展开期间右侧显示目标节点）。
    let pendingTarget: NodeSummary?

    @Environment(AppModel.self) private var model
    @AppStorage("home.scrubCoachSeen") private var coachSeen = false
    @State private var scrubIndex: Int?
    @State private var startIndex = 0
    @State private var tickToken = 0
    @State private var ticking = false

    private var choices: [NodeSummary] { model.regionChoices[scene.id] ?? [] }
    private var shown: NodeSummary {
        if let i = scrubIndex, choices.indices.contains(i) { return choices[i] }
        return pendingTarget ?? scene.selected
    }

    var body: some View {
        HStack(alignment: .center, spacing: ZTokens.Space.n4) {
            leading
            Spacer(minLength: ZTokens.Space.n3)
            trailing
        }
        .padding(.vertical, HMetrics.rowVertical)
        .padding(.horizontal, HMetrics.rowHorizontal)
        .background(scrubIndex != nil ? AnyShapeStyle(ZAccentStyle(opacity: 0.05)) : AnyShapeStyle(Color.clear))
        .overlay(alignment: .bottom) { scrubTrack }
        .overlay(alignment: .bottom) { coach }
        .overlay {
            if scrubbable {
                HorizontalPanOverlay(onTap: openDetail, onBegan: began, onChanged: changed, onEnded: ended)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !scrubbable { openDetail() } }
        .sensoryFeedback(.selection, trigger: tickToken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(verbatim: scrubbable ? "上下轻扫切换地区，轻点两下查看详情" : "轻点两下查看详情"))
        .accessibilityAction { openDetail() }
        .modifier(AdjustableIf(enabled: scrubbable) { step in adjust(step) })
        .task(id: scrubbable) {
            if scrubbable, choices.isEmpty { await model.loadRegionChoices(sceneId: scene.id) }
        }
    }

    // MARK: 左右两栏

    private var leading: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            Text(verbatim: scene.name)
                .zType(.headline).fontWeight(.regular)
                .foregroundStyle(ZTokens.Colors.screenT1)
            meta
        }
    }

    @ViewBuilder
    private var meta: some View {
        if isProbing {
            VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                Text(verbatim: scene.available > 0 ? "\(scene.available) 个可用 · 检测中" : "检测中")
                    .zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
                ProbeBar().frame(width: HMetrics.probeBarWidth)
            }
        } else if scene.source == .subscriptionGroup {
            Text(verbatim: "订阅分组").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
        } else if scene.available <= 0 {
            Text(verbatim: "暂无可用节点").zType(.footnote).foregroundStyle(ZTokens.Colors.screenRed)
        } else {
            Text(verbatim: "\(scene.available) 个可用").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: ZTokens.Space.n1) {
            HStack(spacing: ZTokens.Space.n3) {
                ZFlag(shown.region, isHighlighted: ticking)
                Text(verbatim: shown.name)
                    .zType(.headline).fontWeight(.regular)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            if let ex = scene.exceptions.first {
                HStack(spacing: ZTokens.Space.n2) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(ZTokens.Colors.screenAmber)
                    Text(verbatim: "\(ex.app)：\(ex.node.name)")
                }
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .lineLimit(1)
            } else if let note = scene.note {
                Text(verbatim: note).zType(.caption).foregroundStyle(ZTokens.Colors.screenT3).lineLimit(1)
            }
        }
        .multilineTextAlignment(.trailing)
    }

    // MARK: 滑动

    @ViewBuilder
    private var scrubTrack: some View {
        if scrubIndex != nil, choices.count > 1 {
            HStack(spacing: ZTokens.Space.n1) {
                ForEach(choices.indices, id: \.self) { i in
                    Capsule().fill(i == scrubIndex ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZTokens.Colors.screenT4))
                        .frame(height: HMetrics.barThin + 1)
                }
            }
            .padding(.horizontal, HMetrics.rowHorizontal)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var coach: some View {
        if showsCoach, !coachSeen, scrubIndex == nil {
            CoachHint(text: "左右滑动以切换地区")
                .offset(y: ZTokens.Space.n4)
                .allowsHitTesting(false)
        }
    }

    private func began() {
        coachSeen = true
        if model.pendingChange?.sceneId == scene.id { model.cancelPendingChange() }
        startIndex = choices.firstIndex { $0.region == shown.region } ?? 0
        if choices.isEmpty { Task { await model.loadRegionChoices(sceneId: scene.id) } }
    }

    private func changed(_ dx: CGFloat) {
        guard !choices.isEmpty else { return }
        let i = min(choices.count - 1, max(0, startIndex + Int((dx / HMetrics.scrubStep).rounded())))
        guard i != scrubIndex else { return }
        let first = scrubIndex == nil
        withAnimation(ZMotion.standard) { scrubIndex = i }
        if !first || i != startIndex { flashTick() }
    }

    private func ended(_: CGFloat) {
        defer { withAnimation(ZMotion.standard) { scrubIndex = nil } }
        guard let i = scrubIndex, choices.indices.contains(i) else { return }
        let target = choices[i]
        if target.id != scene.selected.id {
            Task { await model.beginSceneChange(sceneId: scene.id, to: target) }
        }
    }

    private func adjust(_ step: Int) {
        guard !choices.isEmpty else { return }
        let cur = choices.firstIndex { $0.region == shown.region } ?? 0
        let i = min(choices.count - 1, max(0, cur + step))
        guard i != cur else { return }
        Task { await model.beginSceneChange(sceneId: scene.id, to: choices[i]) }
    }

    private func flashTick() {
        tickToken &+= 1
        ticking = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ZTokens.Time.micro * 1_000_000_000))
            ticking = false
        }
    }

    private func openDetail() { model.present(.scene(id: scene.id)) }

    private var a11yLabel: String {
        var parts = [scene.name]
        if isProbing { parts.append("检测中") }
        else if scene.source == .subscriptionGroup { parts.append("订阅分组") }
        else { parts.append(scene.available > 0 ? "\(scene.available) 个可用" : "暂无可用节点") }
        parts.append("\(HRegionName.name(shown.region)) \(shown.name)")
        if let ex = scene.exceptions.first { parts.append("\(ex.app) 固定使用 \(ex.node.name)") }
        if let note = scene.note { parts.append(note) }
        return parts.joined(separator: "，")
    }
}

/// 仅在 enabled 时挂 VoiceOver 可调整操作。
@MainActor
private struct AdjustableIf: ViewModifier {
    let enabled: Bool
    let adjust: (Int) -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: adjust(1)
                case .decrement: adjust(-1)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}

#Preview {
    HPreview(model: .preview()) { HomeView() }
}

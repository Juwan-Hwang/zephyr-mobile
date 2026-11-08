// 首页场景行（原型 `.row[data-scene]`）。
//
// 左：场景名 + 状态（"9 个可用" / "订阅分组" / 检测中进度 / 无可用节点）
// 右：地区码 + 当前节点；第二行例外（🔒 Claude：US-Fixed-01）或备注（Netflix 完整片库）
// 服务不可用（原型 11 zero.png，契约 §14.z Scene.services）：左"Claude 不可用"（红），右第二行"GPT、Gemini 正常"。
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("home.scrubCoachSeen") private var coachSeen = false
    @State private var scrubIndex: Int?
    @State private var startIndex = 0
    @State private var tickToken = 0
    @State private var ticking = false
    @State private var pressed = false

    private var choices: [NodeSummary] { model.regionChoices[scene.id] ?? [] }
    private var services: SceneServiceSummary { SceneServiceSummary(scene.services) }
    private var shown: NodeSummary {
        if let i = scrubIndex, choices.indices.contains(i) { return choices[i] }
        return pendingTarget ?? scene.selected
    }

    var body: some View {
        // 大字体（原型 19 xl.png）：左右两栏改为上下堆叠，节点名与锁定说明不再截断。
        let stacked = typeSize >= .xxxLarge
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n2))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: ZTokens.Space.n4))
        layout {
            leading
            if !stacked { Spacer(minLength: ZTokens.Space.n3) }
            trailing(stacked: stacked)
        }
        .padding(.vertical, HMetrics.rowVertical)
        .padding(.horizontal, HMetrics.rowHorizontal)
        .background(rowBackground)
        .overlay(alignment: .bottom) { scrubTrack }
        .overlay(alignment: .bottom) { coach }
        .overlay {
            if scrubbable {
                HorizontalPanOverlay(onTap: openDetail, onBegan: began, onChanged: changed, onEnded: ended,
                                     onPressChanged: { pressed = $0 })
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !scrubbable { openDetail() } }
        .sensoryFeedback(.selection, trigger: tickToken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(scrubbable ? LocalizedStringKey("上下轻扫切换地区，轻点两下查看详情") : LocalizedStringKey("轻点两下查看详情")))
        .accessibilityAction { openDetail() }
        .modifier(AdjustableIf(enabled: scrubbable) { step in adjust(step) })
        .task(id: scrubbable) {
            if scrubbable, choices.isEmpty { await model.loadRegionChoices(sceneId: scene.id) }
        }
    }

    private var rowBackground: AnyShapeStyle {
        if scrubIndex != nil { return AnyShapeStyle(ZAccentStyle(opacity: 0.05)) }
        return pressed ? AnyShapeStyle(ZTokens.Colors.screenPressed) : AnyShapeStyle(Color.clear)
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
                Text(verbatim: scene.available > 0 ? ZL.f("%d 个可用 · 检测中", scene.available) : ZL.tr("检测中"))
                    .zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
                ProbeBar().frame(width: HMetrics.probeBarWidth)
            }
        } else if let down = services.unavailableText {
            Text(verbatim: down).zType(.footnote).foregroundStyle(ZTokens.Colors.screenRed)
        } else if scene.source == .subscriptionGroup {
            Text("订阅分组").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
        } else if scene.available <= 0 {
            Text("暂无可用节点").zType(.footnote).foregroundStyle(ZTokens.Colors.screenRed)
        } else {
            Text("\(scene.available) 个可用").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
        }
    }

    private func trailing(stacked: Bool) -> some View {
        VStack(alignment: stacked ? .leading : .trailing, spacing: ZTokens.Space.n1) {
            HStack(spacing: ZTokens.Space.n3) {
                ZFlag(shown.region, isHighlighted: ticking)
                // 原型 `.ex` font-size 15（REVIEW H-P2-3）。
                Text(verbatim: shown.name)
                    .hFont(HMetrics.rowValueFont, relativeTo: .subheadline)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(stacked ? nil : 1)
                    .contentTransition(.opacity)
            }
            if let ok = services.healthyText {
                Text(verbatim: ok).zType(.caption).foregroundStyle(ZTokens.Colors.screenT3).lineLimit(stacked ? nil : 1)
            } else if let ex = scene.exceptions.first {
                HStack(spacing: ZTokens.Space.n2) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(ZTokens.Colors.screenAmber)
                        .opacity(HMetrics.pinIconOpacity)
                    Text(verbatim: "\(ex.app)：\(ex.node.name)")
                }
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .lineLimit(stacked ? nil : 1)
            } else if let note = scene.note {
                Text(verbatim: note).zType(.caption).foregroundStyle(ZTokens.Colors.screenT3).lineLimit(stacked ? nil : 1)
            }
        }
        .multilineTextAlignment(stacked ? .leading : .trailing)
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
            CoachHint(text: ZL.tr("左右滑动以切换地区"))
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
        if isProbing { parts.append(ZL.tr("检测中")) }
        else if services.replacesRowStatus { parts.append(services.spoken ?? "") }
        else if scene.source == .subscriptionGroup { parts.append(ZL.tr("订阅分组")) }
        else { parts.append(scene.available > 0 ? ZL.f("%d 个可用", scene.available) : ZL.tr("暂无可用节点")) }
        parts.append("\(HRegionName.name(shown.region)) \(shown.name)")
        if let ex = scene.exceptions.first { parts.append(ZL.s("%@ 固定使用 %@", ex.app, ex.node.name)) }
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

#Preview("服务不可用（原型 11）") {
    let tested = ZFormat.nowMillis()
    let scene = Scene(id: "ai", kind: .ai, name: "AI", available: 9,
                      selected: NodeSummary(id: 2, name: "新加坡 02", region: "SG", protocol: "Hy2", latencyMs: 74),
                      source: .auto, testedAt: tested,
                      exceptions: [SceneException(app: "Claude", node: NodeSummary(id: 9, name: "US-Fixed-01", region: "US", protocol: "VLESS"))],
                      services: [ServiceHealth(appId: "chatgpt", name: "GPT", ok: true, checkedAt: tested),
                                 ServiceHealth(appId: "claude", name: "Claude", ok: false, checkedAt: tested),
                                 ServiceHealth(appId: "gemini", name: "Gemini", ok: true, checkedAt: tested)])
    return HPreview(model: .preview()) {
        SceneRow(scene: scene, scrubbable: false, showsCoach: false, isProbing: false, pendingTarget: nil)
    }
}

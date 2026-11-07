// 切换地区确认卡（原型 `.confirm .cf`，截图 scrub.png）：
//   ● 更改 GPT 和 Gemini 的出口 IP？
//   SG 198.51.100.7 → JP 203.0.113.61
//   Claude 保持不变。
//   [更改] [取消]
// 数据来自 engine.previewSceneChange；预览返回前显示占位。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct SceneChangeConfirm: View {
    let change: PendingSceneChange
    let sceneName: String
    @Environment(AppModel.self) private var model
    /// 出现时把 VoiceOver 焦点移到标题；卡片不是模态，不锁焦点（REVIEW H-P1-8）。
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                Circle().fill(ZTokens.Colors.screenAmber)
                    .frame(width: ZTokens.Space.n2, height: ZTokens.Space.n2)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                Text(verbatim: title).zType(.footnote).fontWeight(.medium).foregroundStyle(ZTokens.Colors.screenT1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            ExitIPLine(change: change.exit, fallbackFrom: change.from.region, fallbackTo: change.to.region)
            if let kept = keptText {
                Text(verbatim: kept).zType(.caption).foregroundStyle(ZTokens.Colors.screenT3)
            }
            HStack(spacing: ZTokens.Space.n3) {
                ZButton("更改", fullWidth: true, isLoading: change.exit == nil) {
                    Task { await model.confirmPendingChange() }
                }
                ZButton("取消", kind: .ghost, fullWidth: true) {
                    withAnimation(ZMotion.slow) { model.cancelPendingChange() }
                }
            }
            .padding(.top, ZTokens.Space.n3)
        }
        .padding(ZTokens.Space.n4)
        .background(RoundedRectangle(cornerRadius: ZTokens.Radius.md, style: .continuous).fill(ZTrackFill()))
        .overlay {
            RoundedRectangle(cornerRadius: ZTokens.Radius.md, style: .continuous)
                .strokeBorder(ZTokens.Colors.screenHl, lineWidth: HMetrics.hairline)
        }
        .padding(.horizontal, HMetrics.rowHorizontal)
        .padding(.bottom, ZTokens.Space.n4)
        .accessibilityElement(children: .contain)
        .onAppear { titleFocused = true }
    }

    /// "更改 GPT 和 Gemini 的出口 IP？"；没有受影响 App 列表时用场景名。
    private var title: String {
        let apps = change.exit?.affectedApps ?? []
        let who = apps.isEmpty ? sceneName : Self.join(apps)
        return "更改 \(who) 的出口 IP？"
    }

    private var keptText: String? {
        guard let kept = change.exit?.unchangedApps, !kept.isEmpty else { return nil }
        return "\(Self.join(kept)) 保持不变。"
    }

    /// ["GPT","Gemini","Claude"] → "GPT、Gemini 和 Claude"
    static func join(_ xs: [String]) -> String {
        switch xs.count {
        case 0: return ""
        case 1: return xs[0]
        default: return xs.dropLast().joined(separator: "、") + " 和 " + xs[xs.count - 1]
        }
    }
}

/// 出口 IP 变化行（等宽）：SG 198.51.100.7 → JP 203.0.113.61。也用于指令预览卡与全局模式。
@MainActor
struct ExitIPLine: View {
    let change: ExitChange?
    var fallbackFrom: String = ""
    var fallbackTo: String = ""

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Text(verbatim: side(change?.fromRegion ?? fallbackFrom, change?.fromIp))
                .foregroundStyle(ZTokens.Colors.screenT2)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(ZQuaternaryText())
            Text(verbatim: side(change?.toRegion ?? fallbackTo, change?.toIp))
                .foregroundStyle(ZTokens.Colors.screenT1)
        }
        .zMono(.small)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .redacted(reason: change == nil ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
    }

    private func side(_ region: String, _ ip: String?) -> String {
        ip.map { "\(region) \($0)" } ?? region
    }

    private var a11y: String {
        guard let c = change else { return "正在获取出口 IP" }
        return "出口从 \(HRegionName.name(c.fromRegion)) \(c.fromIp ?? "") 变为 \(HRegionName.name(c.toRegion)) \(c.toIp ?? "")"
    }
}

#Preview {
    let from = NodeSummary(id: 1, name: "新加坡 02", region: "SG", protocol: "Hy2")
    let to = NodeSummary(id: 2, name: "东京 03", region: "JP", protocol: "VLESS")
    let exit = ExitChange(sceneId: "ai", fromRegion: "SG", fromIp: "198.51.100.7", toRegion: "JP", toIp: "203.0.113.61",
                          affectedApps: ["GPT", "Gemini"], unchangedApps: ["Claude"])
    return HPreview(model: .preview()) {
        VStack {
            SceneChangeConfirm(change: PendingSceneChange(sceneId: "ai", from: from, to: to, exit: exit), sceneName: "AI")
            SceneChangeConfirm(change: PendingSceneChange(sceneId: "ai", from: from, to: to, exit: nil), sceneName: "AI")
        }
    }
}

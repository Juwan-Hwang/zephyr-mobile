// 契约 §16.d 预览卡（原型 render() 的 `.pv`）：
//   例外    Gemini 使用日本节点 / 3 个可用，将使用东京 03。/ [出口 IP 将更改 SG … → JP …]
//           / Claude 将不再使用固定出口 US-Fixed-01。/ 日本节点均不可用时，Gemini 将暂停。/ [应用]
//   整场景  视频 使用日本节点 / … / 日本节点均不可用时，将使用场景中的其他节点。/ [应用]
//   直连    GitHub 直连 / GitHub 的流量将不经过代理。/ [出口 IP 将更改 TW … → 本机网络]
//           / 仅在 Zephyr 中生效，订阅配置保持原样。/ [应用]
//   无节点  Gemini 使用英国节点 / AI 场景中没有英国节点。/ [无可用节点]（禁用）
// 例外是单节点钉住，节点不可用时该服务暂停（§14.y），视频服务例外也用“将暂停”，不承诺做不到的回退。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct CommandPlanCard: View {
    let plan: CommandPlan
    let isApplying: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            Text(verbatim: title).zType(.headline).fontWeight(.regular).foregroundStyle(ZTokens.Colors.screenT1)
            Text(verbatim: summary).zType(.footnote).foregroundStyle(ZColor.t3)

            if let line = ipLine {
                VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                    HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                        Circle().fill(ZTokens.Colors.screenAmber)
                            .frame(width: ZTokens.Space.n2, height: ZTokens.Space.n2)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        Text("出口 IP 将更改").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT1)
                    }
                    line
                }
                .padding(ZTokens.Space.n4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZTokens.Radius.md, style: .continuous).fill(ZTrackFill().opacity(0.6)))
                .padding(.top, ZTokens.Space.n4)
            }

            ForEach(notes, id: \.self) { note in
                Text(verbatim: note).zType(.footnote).foregroundStyle(ZColor.t3)
                    .padding(.top, ZTokens.Space.n4)
            }

            ZButton(LocalizedStringKey(plan.canApply ? "应用" : "无可用节点"), size: .large, fullWidth: true, isLoading: isApplying, action: onApply)
                .disabled(!plan.canApply)
                .padding(.top, ZTokens.Space.n5)
        }
        .padding(ZTokens.Space.n5)
        .zSurface(.raised, cornerRadius: HMetrics.cardRadius)
        .padding(.horizontal, HMetrics.cardInset)
        .accessibilityElement(children: .contain)
    }

    // MARK: 文案（纯值，单测直接读）

    var title: String {
        switch plan {
        case .exit(let e): ZL.s("%1$@ 使用%2$@节点", e.who, HRegionName.name(e.regionCode))
        case .noNodes(let who, _, let code): ZL.s("%1$@ 使用%2$@节点", who, HRegionName.name(code))
        case .direct(let d): ZL.s("%@ 直连", d.who)
        }
    }

    var summary: String {
        switch plan {
        case .exit(let e): ZL.s("%1$@ 个可用，将使用%2$@。", ZFormat.count(Int64(e.available)), e.node.name)
        case .noNodes(_, let scene, let code): ZL.s("%1$@ 场景中没有%2$@节点。", scene, HRegionName.name(code))
        case .direct(let d): ZL.s("%@ 的流量将不经过代理。", d.who)
        }
    }

    /// 出口 IP 行之后的说明行（原型依次：释放固定出口、不可用时的行为 / 仅在 Zephyr 中生效）。
    var notes: [String] {
        switch plan {
        case .exit(let e):
            var out: [String] = []
            if let pin = e.releasesPin { out.append(ZL.s("%1$@ 将不再使用固定出口 %2$@。", e.who, pin)) }
            let region = HRegionName.name(e.regionCode)
            out.append(e.isException ? ZL.s("%1$@节点均不可用时，%2$@ 将暂停。", region, e.who)
                                     : ZL.s("%@节点均不可用时，将使用场景中的其他节点。", region))
            return out
        case .direct: return [ZL.tr("仅在 Zephyr 中生效，订阅配置保持原样。")]
        case .noNodes: return []
        }
    }

    var buttonTitle: String { plan.canApply ? ZL.tr("应用") : ZL.tr("无可用节点") }

    /// 地区与当前出口不同才显示（原型 `same`）；直连恒显示“→ 本机网络”。
    var hasIPLine: Bool {
        switch plan {
        case .exit(let e): e.exit != nil
        case .direct: true
        case .noNodes: false
        }
    }

    /// 直连出口行左侧：“TW 198.51.100.30”（出口未知为空，只显示“→ 本机网络”）。
    var directFrom: String? {
        guard case .direct(let d) = plan else { return nil }
        return [d.fromRegion, d.fromIp].compactMap { $0 }.joined(separator: " ")
    }

    private var ipLine: AnyView? {
        switch plan {
        case .exit(let e):
            guard let x = e.exit else { return nil }
            return AnyView(ExitIPLine(change: x))
        case .direct:
            let from = directFrom ?? ""
            return AnyView(HStack(spacing: ZTokens.Space.n3) {
                if !from.isEmpty { Text(verbatim: from).foregroundStyle(ZColor.t2) }
                Image(systemName: "arrow.forward").font(.caption2).foregroundStyle(ZQuaternaryText())
                Text("本机网络").foregroundStyle(ZTokens.Colors.screenT1)
            }
            .zMono(.small)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: from.isEmpty ? ZL.tr("本机网络") : "\(from), \(ZL.tr("本机网络"))")))
        case .noNodes:
            return nil
        }
    }
}

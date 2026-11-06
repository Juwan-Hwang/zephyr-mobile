// 指令预览卡（原型 `.pv`）：
//   Gemini 使用日本节点
//   3 个可用，将使用东京 03。
//   ┌ ● 出口 IP 将更改          ┐
//   └ SG 198.51.100.7 → JP 203.0.113.61 ┘
//   日本节点均不可用时，Gemini 将暂停。
//   [应用]

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct CommandPreviewCard: View {
    let preview: CommandModel.Preview
    let parse: CommandParse
    let isApplying: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            Text(verbatim: title).zType(.headline).fontWeight(.regular).foregroundStyle(ZTokens.Colors.textPrimary)
            Text(verbatim: summary).zType(.footnote).foregroundStyle(ZTokens.Colors.textTertiary)

            if let exit = preview.exit, exit.fromIp != exit.toIp || exit.fromRegion != exit.toRegion {
                VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                    HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                        Circle().fill(ZTokens.Colors.textWarning)
                            .frame(width: ZTokens.Space.n2, height: ZTokens.Space.n2)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        Text(verbatim: "出口 IP 将更改").zType(.footnote).foregroundStyle(ZTokens.Colors.textPrimary)
                    }
                    ExitIPLine(change: exit)
                }
                .padding(ZTokens.Space.n4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZTokens.Radius.md, style: .continuous).fill(ZTrackFill().opacity(0.6)))
                .padding(.top, ZTokens.Space.n4)
            }

            if let foot = footnote {
                Text(verbatim: foot).zType(.footnote).foregroundStyle(ZTokens.Colors.textTertiary)
                    .padding(.top, ZTokens.Space.n4)
            }

            ZButton("应用", size: .large, fullWidth: true, isLoading: isApplying, action: onApply)
                .disabled(preview.node == nil)
                .padding(.top, ZTokens.Space.n5)
        }
        .padding(ZTokens.Space.n5)
        .zSurface(.raised, cornerRadius: HMetrics.cardRadius)
        .padding(.horizontal, HMetrics.cardInset)
        .accessibilityElement(children: .contain)
    }

    /// "Gemini 使用日本节点"；识别不出服务/地区时用引擎给的标题。
    private var title: String {
        if let svc = parse.serviceName, let rg = parse.regionName { return "\(svc) 使用\(rg)节点" }
        return preview.suggestion.title
    }

    /// "3 个可用，将使用东京 03。"
    private var summary: String {
        guard let node = preview.node else { return preview.suggestion.subtitle ?? "" }
        if let n = preview.candidateCount, n > 0 { return "\(n) 个可用，将使用\(node.name)。" }
        return "将使用\(node.name)（\(ZFormat.latency(node.latencyMs))）。"
    }

    /// "日本节点均不可用时，Gemini 将暂停。"（AI 场景）/ "…将使用场景中的其他节点。"（其他场景）
    private var footnote: String? {
        guard let rg = parse.regionName else { return nil }
        if preview.sceneId == "ai", let svc = parse.serviceName { return "\(rg)节点均不可用时，\(svc) 将暂停。" }
        if preview.sceneId != nil { return "\(rg)节点均不可用时，将使用场景中的其他节点。" }
        return nil
    }
}

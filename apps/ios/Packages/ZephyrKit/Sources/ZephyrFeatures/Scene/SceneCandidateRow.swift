// 场景候选行（原型 `#poolList .li`）：地区码 · 名称 · （Claude 固定）· 延迟。当前选中：名称高亮 + 勾。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct SceneCandidateRow: View {
    let node: NodeSummary
    let isSelected: Bool
    /// 该节点被某个 App 固定（"Claude 固定"）。
    let pinnedFor: String?

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            HFlag(region: node.region)
            Text(verbatim: node.name)
                .zType(.body)
                .foregroundStyle(isSelected ? ZTokens.Colors.textPrimary : ZTokens.Colors.textSecondary)
                .fontWeight(isSelected ? .medium : .regular)
                .lineLimit(1)
            Spacer(minLength: ZTokens.Space.n3)
            if let pinnedFor {
                Text(verbatim: "\(pinnedFor) 固定").zType(.caption).foregroundStyle(ZTokens.Colors.textTertiary)
            }
            Text(verbatim: ZFormat.latency(node.latencyMs))
                .zMono(.body)
                .foregroundStyle(latencyColor)
                .frame(minWidth: ZTokens.Space.n8, alignment: .trailing)
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ZAccentStyle())
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.vertical, ZTokens.Space.n4)
        .padding(.horizontal, ZTokens.Space.n5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var latencyColor: Color {
        guard let ms = node.latencyMs else { return ZTokens.Colors.textTertiary }
        return ms < 0 || ms >= ZTokens.LatencyThreshold.slow ? ZTokens.LatencyThreshold.color(Int(ms)) : ZTokens.Colors.textTertiary
    }

    private var a11y: String {
        var s = "\(HRegionName.zh(node.region)) \(node.name)，\(ZFormat.latency(node.latencyMs))"
        if let pinnedFor { s += "，\(pinnedFor) 固定" }
        return s
    }
}

#Preview {
    VStack(spacing: 0) {
        SceneCandidateRow(node: NodeSummary(id: 1, name: "台北 02", region: "TW", protocol: "VLESS", latencyMs: 48), isSelected: false, pinnedFor: nil)
        SceneCandidateRow(node: NodeSummary(id: 2, name: "新加坡 02", region: "SG", protocol: "Hy2", latencyMs: 74), isSelected: true, pinnedFor: nil)
        SceneCandidateRow(node: NodeSummary(id: 3, name: "US-Fixed-01", region: "US", protocol: "VLESS", latencyMs: 188), isSelected: false, pinnedFor: "Claude")
    }
    .zPageBackground()
}

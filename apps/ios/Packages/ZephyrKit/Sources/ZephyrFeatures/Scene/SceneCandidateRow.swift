// 场景候选行（原型 `#poolList .li`）：地区码 · 名称 · （Claude 固定）· 延迟。当前选中：名称高亮 + 勾。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct SceneCandidateRow: View {
    let node: NodeSummary
    let isSelected: Bool
    /// 该节点被某个 App 固定（"Claude 固定"）。
    let pinnedFor: String?

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            ZFlag(node.region)
            // 原型 `.li`：15pt、节点名全部 t1，选中只加粗与勾（REVIEW-Q1 H-P2-10）。
            Text(verbatim: node.name)
                .zType(.zRowValue)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .fontWeight(isSelected ? .medium : .regular)
                .lineLimit(1)
            Spacer(minLength: ZTokens.Space.n3)
            if let pinnedFor {
                Text("\(pinnedFor) 固定").zType(.caption).foregroundStyle(ZColor.t3)
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
        .padding(.vertical, Self.verticalPadding)
        .padding(.horizontal, Self.horizontalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 原型 `.li { padding: 13px 14px }`。
    static let verticalPadding: CGFloat = 13
    static let horizontalPadding: CGFloat = 14

    private var latencyColor: Color {
        guard let ms = node.latencyMs else { return ZColor.t3 }
        return ms < 0 || ms >= ZTokens.LatencyThreshold.slow ? ZTokens.LatencyThreshold.color(Int(ms)) : ZColor.t3
    }

    private var a11y: String {
        var s = "\(HRegionName.name(node.region)) \(node.name)，\(ZFormat.latency(node.latencyMs))"
        if let pinnedFor { s += ZL.s("，%@ 固定", pinnedFor) }
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

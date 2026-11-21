// StorageCard — 设置“存储”分组（原型 .gr .meter）：节点与规则 → 双段用量条 → “节点 0.6 GB · 规则 1.9 GB · 可用 3.1 GB”。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct StorageCard: View {
    /// nil = 加载中。
    var info: StorageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
            Text("节点与规则")
                .zType(.body)
                .foregroundStyle(ZTokens.Colors.screenT1)
            ZProgressBar(segments: segments, label: "存储")
            // 规范 §9.2（L-1）：三项分列对齐，不用「A · B · C」中点串联。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n5) { columnTexts }
                VStack(alignment: .leading, spacing: ZTokens.Space.n1) { columnTexts }
            }
            .zType(.caption)
            .foregroundStyle(ZColor.t3)
            .redacted(reason: info == nil ? .placeholder : [])
        }
        .padding(.horizontal, ZTokens.Space.n5 - ZTokens.Space.n1 / 2)
        .padding(.vertical, ZTokens.Space.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("节点与规则，\(caption)"))
    }

    private var columnTexts: some View {
        ForEach(Array(Self.columns(caption).enumerated()), id: \.offset) { _, part in
            Text(verbatim: part).fixedSize()
        }
    }

    private var segments: [ZProgressSegment] {
        guard let i = info else { return [] }
        let total = Double(max(1, i.nodesBytes + i.rulesBytes + i.freeBytes))
        return [ZProgressSegment(id: 0, fraction: Double(i.nodesBytes) / total, tone: .accent),
                ZProgressSegment(id: 1, fraction: Double(i.rulesBytes) / total, tone: .neutral)]
    }

    private var caption: String {
        guard let i = info else { return ZL.tr("节点 0.0 GB · 规则 0.0 GB · 可用 0.0 GB") }
        return ZL.s("节点 %1$@ · 规则 %2$@ · 可用 %3$@", Self.gb(i.nodesBytes), Self.gb(i.rulesBytes), Self.gb(i.freeBytes))
    }

    /// 译文仍以「 · 」分隔三项（沿用既有 key），这里拆成三列显示；无障碍标签用整句。
    nonisolated static func columns(_ caption: String) -> [String] {
        caption.components(separatedBy: " · ").filter { !$0.isEmpty }
    }

    /// 存储统一以 GB 一位小数显示（原型 “0.6 GB”）；不足 0.1 GB 时退回 ZFormat.bytes。
    static func gb(_ bytes: Int64) -> String {
        guard bytes >= 100_000_000 else { return ZFormat.bytes(bytes) }
        let tenths = (bytes + 50_000_000) / 100_000_000
        return "\(tenths / 10).\(tenths % 10) GB"
    }
}

#if DEBUG
#Preview {
    ZSettingsGroup("存储") {
        StorageCard(info: StorageInfo(nodesBytes: 600_000_000, rulesBytes: 1_900_000_000, freeBytes: 3_100_000_000))
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}
#endif

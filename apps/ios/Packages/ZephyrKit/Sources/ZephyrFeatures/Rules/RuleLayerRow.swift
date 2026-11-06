// RuleLayerRow — 匹配顺序的一行（原型 #layers .gr）：序号 / 名称 + 说明 / 类型标签 / 条数；命中行强调色底。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct RuleLayerRow: View {
    var ordinal: Int
    var name: String
    var note: String
    var kind: LayerKind?
    var count: String
    var isHit: Bool

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            Text("\(ordinal)")
                .font(.caption2.monospacedDigit())
                .monospaced()
                .foregroundStyle(ZTokens.Colors.textTertiary.opacity(0.6))
                .frame(minWidth: ZTokens.Space.n5, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).zType(.body).foregroundStyle(ZTokens.Colors.textPrimary)
                Text(note).zType(.caption).foregroundStyle(ZTokens.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let kind { tag(kind) }
            Text(count)
                .font(.footnote.monospacedDigit())
                .monospaced()
                .foregroundStyle(kind == nil ? ZTokens.Colors.textTertiary : ZTokens.Colors.textSecondary)
        }
        .padding(.horizontal, ZTokens.Space.n4 + 2)
        .padding(.vertical, ZTokens.Space.n4)
        .frame(minHeight: LStyle.rowMinHeight)
        .background(isHit ? AnyShapeStyle(TintShapeStyle().opacity(0.09)) : AnyShapeStyle(Color.clear))
        .animation(.easeOut(duration: ZTokens.Time.standard), value: isHit)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHit ? "已命中" : "")
    }

    private func tag(_ k: LayerKind) -> some View {
        let isOverride = k == .override
        return Text(Self.title(k))
            .font(.caption2)
            .monospaced()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(isOverride ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(ZTokens.Colors.textTertiary))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isOverride ? AnyShapeStyle(TintShapeStyle().opacity(0.45)) : AnyShapeStyle(ZTokens.Colors.borderDefault), lineWidth: 1))
    }

    static func title(_ k: LayerKind) -> String {
        switch k {
        case .override: "覆写"
        case .subscription: "订阅"
        case .domain: "域名"
        case .ip: "IP"
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        RuleLayerRow(ordinal: 1, name: "Zephyr 覆写", note: "在订阅之上", kind: .override, count: "14", isHit: false)
        LDivider()
        RuleLayerRow(ordinal: 3, name: "OpenAI", note: "规则集 · 每天更新", kind: .domain, count: "312", isHit: true)
        LDivider()
        RuleLayerRow(ordinal: 8, name: "其余流量", note: "MATCH", kind: nil, count: "其他", isHit: false)
    }
    .lCard()
    .padding()
    .background(LStyle.pageBackground)
}

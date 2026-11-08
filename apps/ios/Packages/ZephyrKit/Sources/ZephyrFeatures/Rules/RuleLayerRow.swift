// RuleLayerRow — 匹配顺序的一行（原型 #layers .gr）：序号 / 名称 + 说明 / 类型标签 / 条数；命中行强调色底。
// 外观交给 ZSettingsRow（index + isHighlighted）与 ZBadge。

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZSettingsRow(verbatim: name, subtitle: note, index: ordinal, isHighlighted: isHit) {
            if let kind {
                ZBadge(verbatim: Self.title(kind), tone: kind == .override ? .accent : .neutral)
            }
            Text(verbatim: count)
                .zMono(.body)
                .foregroundStyle(kind == nil ? ZTokens.Colors.screenT3 : ZTokens.Colors.screenT2)
        }
        .animation(ZMotion.motion(ZMotion.standard, reduceMotion: reduceMotion), value: isHit)
        .accessibilityValue(Text(isHit ? LocalizedStringKey("已命中") : LocalizedStringKey("")))
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
    ZCard(padding: 0) {
        VStack(spacing: 0) {
            RuleLayerRow(ordinal: 1, name: "Zephyr 覆写", note: "在订阅之上", kind: .override, count: "14", isHit: false)
            ZDivider()
            RuleLayerRow(ordinal: 3, name: "OpenAI", note: "规则集 · 每天更新", kind: .domain, count: "312", isHit: true)
            ZDivider()
            RuleLayerRow(ordinal: 8, name: "其余流量", note: "MATCH", kind: nil, count: "其他", isHit: false)
        }
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}

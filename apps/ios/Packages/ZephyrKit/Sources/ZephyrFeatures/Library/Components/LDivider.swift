// LDivider — 分组卡片内的细分隔线。

import SwiftUI
import ZephyrDesign

/// 细分隔线（原型 .gr+.gr border-top 1px var(--hl)）。
struct LDivider: View {
    var leading: CGFloat = 0
    @Environment(\.displayScale) private var scale
    var body: some View {
        Rectangle()
            .fill(ZTokens.Colors.borderSubtle)
            .frame(height: 1 / max(1, scale))
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

// LToggleRow — 带开关的行（原型 .gr + .sw2）。系统 Toggle，绿色与原型一致；整行可点。

import SwiftUI
import ZephyrDesign

struct LToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .zType(.caption)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                }
            }
        }
        .tint(ZTokens.Palette.green500)
        .padding(.horizontal, ZTokens.Space.n4 + 2)
        .padding(.vertical, ZTokens.Space.n3)
        .frame(minHeight: LStyle.rowMinHeight)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

#Preview {
    @Previewable @State var on = true
    LToggleRow("仅在 Wi‑Fi 下更新", isOn: $on)
        .lCard()
        .padding()
        .background(LStyle.pageBackground)
}

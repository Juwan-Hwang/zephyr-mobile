// SubscriptionImportOptions — 四种导入方式的分组列表（原型 ob1 .imp）：图标 + 名称 + ›。

import SwiftUI
import ZephyrDesign

struct SubscriptionImportOptions: View {
    var onSelect: (SubscriptionImportMethod) -> Void
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = ZTokens.Space.n6

    var body: some View {
        ZCard(padding: 0, cornerRadius: ZTokens.Radius.overlay - ZTokens.Space.n1 / 2) {
            VStack(spacing: 0) {
                ForEach(Array(SubscriptionImportMethod.allCases.enumerated()), id: \.element) { i, m in
                    if i > 0 { ZDivider() }
                    Button { onSelect(m) } label: { row(m) }
                        .buttonStyle(ZRowButtonStyle())
                }
            }
        }
    }

    private func row(_ m: SubscriptionImportMethod) -> some View {
        HStack(spacing: ZTokens.Space.n4) {
            Image(systemName: m.systemImage)
                .foregroundStyle(ZTokens.Colors.screenT2)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(verbatim: m.title)
                .zType(.body)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ZQuaternaryText())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ZTokens.Space.n5 + ZTokens.Space.n1)
        .frame(minHeight: ZTokens.Layout.touchMinIos + ZTokens.Space.n5)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubscriptionImportOptions(onSelect: { _ in })
        .padding()
        .zPageBackground()
        .preferredColorScheme(.dark)
}

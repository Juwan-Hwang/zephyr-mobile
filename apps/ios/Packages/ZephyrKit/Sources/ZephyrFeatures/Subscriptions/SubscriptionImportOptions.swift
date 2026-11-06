// SubscriptionImportOptions — 四种导入方式的分组列表（原型 ob1 .imp）。

import SwiftUI
import ZephyrDesign

struct SubscriptionImportOptions: View {
    var onSelect: (SubscriptionImportMethod) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SubscriptionImportMethod.allCases.enumerated()), id: \.element) { i, m in
                if i > 0 { LDivider() }
                Button { onSelect(m) } label: {
                    HStack(spacing: ZTokens.Space.n4) {
                        Image(systemName: m.systemImage)
                            .font(.body)
                            .foregroundStyle(ZTokens.Colors.textSecondary)
                            .frame(width: ZTokens.Space.n6)
                            .accessibilityHidden(true)
                        Text(m.title)
                            .zType(.body)
                            .foregroundStyle(ZTokens.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ZTokens.Colors.textTertiary.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, ZTokens.Space.n6 - 4)
                    .frame(minHeight: ZTokens.Layout.touchMinIos + ZTokens.Space.n5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LRowButtonStyle())
            }
        }
        .lCard(radius: ZTokens.Radius.overlay - 2)
    }
}

#Preview {
    SubscriptionImportOptions(onSelect: { _ in })
        .padding()
        .background(LStyle.pageBackground)
}

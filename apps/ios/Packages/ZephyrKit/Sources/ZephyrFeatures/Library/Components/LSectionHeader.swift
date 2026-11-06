// LSectionHeader — 分组标题（原型 .sec：13pt 三级色，左标题右注释，上 24 下 8）。

import SwiftUI
import ZephyrDesign

struct LSectionHeader: View {
    var title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title; self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: ZTokens.Space.n3)
            if let trailing { Text(trailing) }
        }
        .zType(.footnote)
        .foregroundStyle(ZTokens.Colors.textTertiary)
        .padding(.horizontal, LStyle.titleInset)
        .padding(.top, ZTokens.Space.n6)
        .padding(.bottom, ZTokens.Space.n3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    LSectionHeader("匹配顺序", trailing: "从上到下")
        .background(LStyle.pageBackground)
}

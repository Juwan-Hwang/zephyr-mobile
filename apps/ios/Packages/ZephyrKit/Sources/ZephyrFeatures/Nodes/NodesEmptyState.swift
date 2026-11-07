// NodesEmptyState — 搜索无结果（原型 .vempty）：“无结果 / 没有与“xxx”匹配的节点”。

import SwiftUI
import ZephyrDesign

struct NodesEmptyState: View {
    var query: String

    var body: some View {
        VStack(spacing: ZTokens.Space.n2) {
            Text("无结果")
                .zType(.headline)
                .fontWeight(.regular)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Text("没有与“\(query.trimmingCharacters(in: .whitespaces))”匹配的节点")
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .multilineTextAlignment(.center)
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NodesEmptyState(query: "火星")
        .zPageBackground()
        .preferredColorScheme(.dark)
}

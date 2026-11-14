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
                .foregroundStyle(ZColor.t3)
                .multilineTextAlignment(.center)
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 查询失败（引擎报错）：此前 NodesModel.failed 没有任何 UI，列表停在骨架（REVIEW-Q1 L-P2-11）。
struct NodesErrorState: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: ZTokens.Space.n2) {
            Text("节点载入失败")
                .zType(.headline)
                .fontWeight(.regular)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Text("请检查网络后重试")
                .zType(.footnote)
                .foregroundStyle(ZColor.t3)
                .multilineTextAlignment(.center)
            ZButton("重试", kind: .ghost, action: onRetry)
                .padding(.top, ZTokens.Space.n3)
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zPageBackground()
    }
}

#Preview("失败") {
    NodesErrorState {}
        .preferredColorScheme(.dark)
}

#Preview {
    NodesEmptyState(query: "火星")
        .zPageBackground()
        .preferredColorScheme(.dark)
}

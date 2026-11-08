// SubscriptionReviewSheet — “更新前显示更改”：先展示 previewUpdate 的 diff，确认后才真正更新。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct SubscriptionReviewSheet: View {
    let review: SubscriptionsModel.Review
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZSheet("更新前确认", doneTitle: nil) {
            VStack(alignment: .leading, spacing: ZTokens.Space.n5) {
                SubscriptionDiffCard(title: title, diff: review.diff, isPreview: true)
                Text("更新会替换订阅中的节点与规则。Zephyr 的覆写与场景选择保持不变。")
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.screenT3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: ZTokens.Space.n3) {
                    ZButton("更新", kind: .primary, size: .large, fullWidth: true) {
                        onConfirm()
                        dismiss()
                    }
                    ZButton("取消", kind: .ghost, size: .large, fullWidth: true) { dismiss() }
                }
                .padding(.top, ZTokens.Space.n3)
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.top, ZTokens.Space.n5)
            .padding(.bottom, ZTokens.Space.n6)
        }
    }

    private var title: String {
        switch review.target {
        case .one(let s): "将更新 \(s.name)"
        case .all(let n): "将更新全部 \(ZFormat.count(Int64(n))) 个订阅"
        }
    }
}

#Preview {
    Color.clear.zSheet(isPresented: .constant(true), detents: [.medium]) {
        SubscriptionReviewSheet(review: .init(target: .all(count: 214),
                                              diff: SubscriptionDiff(addedNodes: 18_204, removedNodes: 2_318, ruleChanges: 41,
                                                                     overridesKept: true, scenesRetested: true)),
                                onConfirm: {})
    }
    .preferredColorScheme(.dark)
}

// SubscriptionsPresentations — 订阅页与“全部订阅”共用的浮层：更新确认 sheet、删除确认、吐司（成功）与顶部横幅（失败）。
// 只挂在当前可见的那一页（isActive），避免两页同时尝试呈现同一个 sheet。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct SubscriptionsPresentations: ViewModifier {
    let model: SubscriptionsModel
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .sheet(item: reviewBinding) { r in
                SubscriptionReviewSheet(review: r) { Task { await model.confirm(r) } }
                    .zSheetPresentation(detents: [.medium, .large])
            }
            .confirmationDialog(Text(verbatim: deleteTitle), isPresented: deletingBinding, titleVisibility: .visible) {
                if let sub = model.deleting {
                    Button(role: .destructive) { Task { await model.delete(sub) } } label: { Text("删除订阅") }
                }
                Button(role: .cancel) { model.deleting = nil } label: { Text("取消") }
            } message: {
                Text("将移除它提供的节点与规则。覆写与场景设置保持不变。")
            }
            .zToast(toastBinding, bottomInset: ZTokens.Space.n6)
            .pageErrorBanner(errorBinding, isActive: isActive)
    }

    // 不可见页的绑定恒为 nil / false，视图结构不随 isActive 变化（不丢滚动位置）。
    private var reviewBinding: Binding<SubscriptionsModel.Review?> {
        Binding(get: { isActive ? model.review : nil }, set: { if isActive { model.review = $0 } })
    }

    private var toastBinding: Binding<ZToastItem?> {
        Binding(get: { isActive ? model.toast : nil }, set: { if isActive { model.toast = $0 } })
    }

    private var errorBinding: Binding<PageError?> {
        Binding(get: { model.error }, set: { model.error = $0 })
    }

    private var deleteTitle: String { model.deleting.map { ZL.s("删除“%@”？", $0.name) } ?? "" }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { isActive && model.deleting != nil }, set: { if !$0 { model.deleting = nil } })
    }
}

extension View {
    func subscriptionsPresentations(_ model: SubscriptionsModel, isActive: Bool = true) -> some View {
        modifier(SubscriptionsPresentations(model: model, isActive: isActive))
    }
}

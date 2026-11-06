// SubscriptionRowStyle — 订阅行在 List 里的卡片外观 + 左滑“更新 / 删除”。
// 卡片底 = ZCardFill（深色玻璃 / 浅色白），分隔线 borderSubtle；删除不用 .destructive role，
// 以免系统在确认前就把行动画移除（删除先弹确认）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct SubscriptionRowStyle: ViewModifier {
    let sub: Subscription
    let model: SubscriptionsModel
    @Environment(\.zAccent) private var accent

    func body(content: Content) -> some View {
        content
            .zCardListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { model.deleting = sub } label: {
                    Label { Text(verbatim: "删除") } icon: { Image(systemName: "trash") }
                }
                .tint(ZTokens.Colors.colorDanger)
                Button { Task { await model.update(sub) } } label: {
                    Label { Text(verbatim: "更新") } icon: { Image(systemName: "arrow.clockwise") }
                }
                .tint(accent.color)
            }
            .accessibilityAction(named: Text(verbatim: "更新")) { Task { await model.update(sub) } }
            .accessibilityAction(named: Text(verbatim: "删除")) { model.deleting = sub }
    }
}

extension View {
    func subscriptionRow(_ sub: Subscription, model: SubscriptionsModel) -> some View {
        modifier(SubscriptionRowStyle(sub: sub, model: model))
    }

    /// List 行套上卡片底与细分隔线，内容自带内边距（ZProfileCard / ZSettingsRow）。
    func zCardListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Rectangle().fill(ZCardFill()))
            .listRowSeparatorTint(ZTokens.Colors.borderSubtle)
    }

    /// List 里不带卡片底的整行（页头、diff 卡）。
    func clearListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

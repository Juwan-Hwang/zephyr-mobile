// SubscriptionRowStyle — 订阅行在 List 里的卡片外观 + 点选设为当前订阅（契约 §22.a）+ 左滑“更新 / 删除”。
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
            // 契约 §22.a：点选设为当前订阅（行内「使用中」随之移动）；当前订阅那行点了不做事。
            .contentShape(Rectangle())
            .onTapGesture { Task { await model.activate(sub) } }
            .accessibilityAddTraits(model.isActive(sub) ? [.isSelected] : [.isButton])
            .zCardListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { model.deleting = sub } label: {
                    Label { Text("删除") } icon: { Image(systemName: "trash") }
                }
                .tint(ZTokens.Colors.screenRed)
                Button { Task { await model.update(sub) } } label: {
                    Label { Text("更新") } icon: { Image(systemName: "arrow.clockwise") }
                }
                .tint(accent.color)
            }
            .accessibilityAction(named: Text("设为当前订阅")) { Task { await model.activate(sub) } }
            .accessibilityAction(named: Text("更新")) { Task { await model.update(sub) } }
            .accessibilityAction(named: Text("删除")) { model.deleting = sub }
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
            .listRowSeparatorTint(ZTokens.Colors.screenHl)
    }

    /// List 里不带卡片底的整行（页头、diff 卡）。
    func clearListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

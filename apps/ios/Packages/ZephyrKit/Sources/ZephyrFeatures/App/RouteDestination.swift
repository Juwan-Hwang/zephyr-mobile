// 页面挂载点（H 与 L 的集成处）。RootView 把 Route / SheetRoute 交给这里，换成具体页面。
//
// ⚠️ L 的页面落地后，只需把下面对应分支的 `RoutePending(...)` 换成真实视图（一行改动），
//    其余导航（深链、指令、首页按钮）都已接好。L 的页面可通过 `@Environment(AppModel.self)` 拿到
//    model.engine / model.push(_:) / model.present(_:)。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct RouteDestination: View {
    let route: Route
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .nodes(let query):
            NodesView(engine: model.engine, query: query)
        case .rules(let query):
            RoutePending(title: "规则", detail: query)          // TODO(L): RulesView
        case .subscriptions:
            RoutePending(title: "订阅", detail: nil)            // TODO(L): SubscriptionsView
        case .settings:
            RoutePending(title: "设置", detail: nil)            // TODO(L): SettingsView
        }
    }
}

/// 资料库 sheet 内容（原型 13，L 负责）。
struct LibraryDestination: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RoutePending(title: "资料库", detail: nil)              // TODO(L): LibrarySheet
    }
}

/// 尚未接入的页面占位。
struct RoutePending: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: ZTokens.Space.n3) {
            Text(verbatim: title).zType(.title).foregroundStyle(ZTokens.Colors.textPrimary)
            if let detail, !detail.isEmpty {
                Text(verbatim: detail).zMono(.body).foregroundStyle(ZTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zPageBackground()
        .navigationTitle(Text(verbatim: title))
    }
}

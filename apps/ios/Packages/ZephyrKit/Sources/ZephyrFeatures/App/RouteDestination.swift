// 页面挂载点（H 与 L 的集成处）。RootView 把 Route / SheetRoute 交给这里，换成具体页面。
// L 的页面只依赖 engine（+ now）；导航动作经 AppModel（push / present），都在主线程。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct RouteDestination: View {
    let route: Route
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .nodes(let query):
            NodesView(engine: model.engine, query: query)
        case .rules(let query):
            RulesView(engine: model.engine, query: query)
        case .subscriptions:
            SubscriptionsView(engine: model.engine, now: model.now)
        case .settings:
            SettingsView(engine: model.engine)
        }
    }
}

/// 资料库 sheet 内容（原型 13）。统计卡 / 行 → 关闭 sheet 后 push 页面或换成场景 sheet。
@MainActor
struct LibraryDestination: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LibrarySheet(engine: model.engine) { item in open(item) }
    }

    private func open(_ item: LibraryItem) {
        switch item {
        case .nodes: model.push(.nodes(query: ""))
        case .subscriptions: model.push(.subscriptions)
        case .rules: model.push(.rules(query: nil))
        case .settings: model.push(.settings)
        case .scenes:
            if let id = model.scenes.first?.id { model.present(.scene(id: id)) } else { model.dismissSheet() }
        }
    }
}

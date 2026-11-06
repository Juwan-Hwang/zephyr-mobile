// 导航目标。首页之外的全屏页面走 NavigationStack（Route），浮层走 sheet（SheetRoute）。
//
// L 负责的页面（节点 / 规则 / 订阅 / 设置 / 资料库）挂在这里：
//   RootView 的 `.navigationDestination(for: Route.self)` 会调用 `RouteDestinations.view(for:)`；
//   L 只需要在 `ZephyrFeatures/…/RouteDestinations+L.swift`（或 NOTES 约定的位置）里提供对应视图。

import Foundation

/// NavigationStack 的页面。`AppModel.path` 是 `[Route]`。
public enum Route: Hashable, Sendable {
    /// 节点页（原型 20/21）。query 为初始搜索词，"" = 全部。
    case nodes(query: String)
    /// 规则页（原型 22/23）。query 为预填的测试输入。
    case rules(query: String?)
    /// 订阅页（原型 24）。
    case subscriptions
    /// 设置页（原型 25）。
    case settings
}

/// 浮层。同一时刻只展示一个 sheet；`AppModel.sheet` 为 nil 时没有浮层。
public enum SheetRoute: Hashable, Identifiable, Sendable {
    /// 资料库（原型 13，L 负责内容）。
    case library
    /// 场景详情（原型 06）。
    case scene(id: String)
    /// 最近连接（原型 08）。`traceID` 非 nil 时直接打开该条的轨迹（原型 09）。
    case connections(traceID: String?)
    /// 今日卡片（原型 14）。
    case today

    public var id: String {
        switch self {
        case .library: "library"
        case .scene(let id): "scene:\(id)"
        case .connections(let t): "connections:\(t ?? "")"
        case .today: "today"
        }
    }
}

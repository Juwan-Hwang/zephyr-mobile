// 代理模式的 App Intents 枚举（快捷指令 / Siri / 控制中心里显示的选项）。

import AppIntents

enum ZephyrModeOption: String, AppEnum, CaseIterable, Sendable {
    case rule, global, direct

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "代理模式")

    static let caseDisplayRepresentations: [ZephyrModeOption: DisplayRepresentation] = [
        .rule: DisplayRepresentation(title: "规则", subtitle: "按规则分流", image: .init(systemName: "arrow.triangle.branch")),
        .global: DisplayRepresentation(title: "全局", subtitle: "全部流量走代理", image: .init(systemName: "globe")),
        .direct: DisplayRepresentation(title: "直连", subtitle: "不经过代理", image: .init(systemName: "arrow.right")),
    ]

    var sharedMode: SharedState.Mode {
        switch self {
        case .rule: .rule
        case .global: .global
        case .direct: .direct
        }
    }
}

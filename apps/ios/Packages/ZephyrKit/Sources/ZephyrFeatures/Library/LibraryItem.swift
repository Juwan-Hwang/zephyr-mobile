// LibraryItem — 资料库 sheet 里可点的目标（原型 13：4 张统计卡 + 4 行）。
// LibrarySheet 只回调 onOpen(item)；由宿主（RouteDestination.LibraryDestination）决定 push 还是 present。

import Foundation

public enum LibraryItem: Hashable, Sendable {
    /// 统计卡“节点” → 节点页
    case nodes
    /// 统计卡“订阅” → 订阅页
    case subscriptions
    /// 统计卡“规则” → 规则页
    case rules
    /// 统计卡“场景” → 场景 sheet（首个场景）
    case scenes
    /// “受信任的 Wi‑Fi” / “本地代理端口” / “设置” → 设置页（契约 v0 无单独路由，见 NOTES-L）
    case settings
}

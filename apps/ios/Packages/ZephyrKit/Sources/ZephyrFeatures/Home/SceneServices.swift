// 场景按服务的健康（契约 §14.z `Scene.services`，REVIEW H-P1-5，原型 11 zero.png）。纯 Swift，便于单测。
//
// 显示规则：
//   - services 为空（未探测过）→ 首页行与场景详情都不显示服务信息。
//   - 首页行：只在有服务不可用时替换左侧状态与右侧第二行——
//       左："Claude 不可用"（红）  右："GPT、Gemini 正常"（t3，取代 🔒 例外 / 备注那一行）
//     全部正常时首页保持原样（原型 04 home.png 没有服务行）；全部不可用时右侧仍显示例外 / 备注。
//   - 场景详情：非空即显示一行服务圆点（原型 `.svc`：实心 = 正常，空心 = 不可用）。
// 名称按契约的内置应用目录顺序原样使用（核心给 "ChatGPT" 就显示 "ChatGPT"）。

import Foundation
import ZephyrKit

struct SceneServiceSummary: Equatable, Sendable {
    let failing: [String]
    let healthy: [String]

    init(_ services: [ServiceHealth]) {
        failing = services.filter { !$0.ok }.map(\.name)
        healthy = services.filter(\.ok).map(\.name)
    }

    /// 有任何服务数据（场景详情显示服务行的条件）。
    var isEmpty: Bool { failing.isEmpty && healthy.isEmpty }

    /// 首页行是否替换为服务状态（至少一个不可用）。
    var replacesRowStatus: Bool { !failing.isEmpty }

    /// 首页行左侧红字："Claude 不可用"。
    var unavailableText: String? {
        failing.isEmpty ? nil : ZL.s("%@ 不可用", Self.join(failing))
    }

    /// 首页行右侧第二行："GPT、Gemini 正常"。只有部分不可用时才有。
    var healthyText: String? {
        guard !failing.isEmpty, !healthy.isEmpty else { return nil }
        return ZL.s("%@ 正常", Self.join(healthy))
    }

    /// VoiceOver："Claude 不可用，ChatGPT、Gemini 正常" / "ChatGPT、Claude、Gemini 均正常" / "Netflix 正常"。
    var spoken: String? {
        if isEmpty { return nil }
        if failing.isEmpty { return ZL.s(healthy.count > 1 ? "%@ 均正常" : "%@ 正常", Self.join(healthy)) }
        if healthy.isEmpty { return ZL.s(failing.count > 1 ? "%@ 均不可用" : "%@ 不可用", Self.join(failing)) }
        return ZL.s("%1$@ 不可用，%2$@ 正常", Self.join(failing), Self.join(healthy))
    }

    static func join(_ names: [String]) -> String { names.joined(separator: ZL.tr("、")) }
}

// 命令搜索（契约 §9）的真实实现：规则走 Rust 规则引擎、节点查询与最快节点走 mmap 节点库，≤ 8 条。
// 规则与 Mock 一致：像域名/IP → test_rule；"全局/规则/直连" → switch_mode；"连接/断开" → toggle_connection（执行类：整词或前缀 ≥ 2）；
// 命中地区/城市/运营商/标签 → open_node_query + 该结果里有效期内最快节点 switch_node；页面名 → open_page。

import Foundation
import ZephyrKit

extension CoreEngine {
    static let commandModes: [(String, ZephyrKit.ProxyMode, [String])] = [
        ("全局", .global, ["全局", "global"]), ("规则", .rule, ["规则", "rule"]), ("直连", .direct, ["直连", "direct"]),
    ]
    static let commandPages: [(String, String, [String])] = [
        ("节点", "nodes", ["节点", "nodes", "node"]), ("订阅", "subscriptions", ["订阅", "sub", "subscriptions"]),
        ("规则", "rules", ["规则", "rules"]), ("场景", "scenes", ["场景", "scene"]), ("设置", "settings", ["设置", "settings"]),
        ("连接列表", "connections", ["连接列表", "connections"]), ("日志", "logs", ["日志", "logs", "log"]), ("今日", "today", ["今日", "today"]),
    ]

    /// 每种模式一条完整文案（不拼“切换到 + 模式名 + 模式”），译文才能按语言调整语序。
    static func switchModeTitle(_ mode: ZephyrKit.ProxyMode) -> String {
        switch mode {
        case .global: ZL.tr("切换到全局模式")
        case .rule: ZL.tr("切换到规则模式")
        case .direct: ZL.tr("切换到直连模式")
        }
    }

    static func looksLikeHost(_ q: String) -> Bool {
        guard !q.contains(where: { $0.isWhitespace }), q.count >= 3 else { return false }
        if q.contains(":"), q.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) { return true }   // IPv6
        let labels = q.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        if labels.count == 4, labels.allSatisfy({ UInt8($0) != nil }) { return true }                     // IPv4
        return labels.last!.allSatisfy { $0.isLetter } && q.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    func liveCommandSuggestions(input: String) async -> [CommandSuggestion] {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = raw.lowercased()
        var it = connectionState().makeAsyncIterator()
        let state = await it.next()
        let on = state.map { $0.status == .connected || $0.status == .connecting } ?? false
        let toggle = CommandSuggestion(kind: .toggleConnection, title: ZL.tr(on ? "断开连接" : "连接"),
                                       subtitle: ZL.tr(on ? "当前已连接" : "当前未连接"), payload: on ? "disconnect" : "connect")
        if q.isEmpty {
            var out = [toggle]
            if let best = await fastest(query: "") {
                out.append(CommandSuggestion(kind: .switchNode, title: ZL.s("切到 %@", best.name),
                                             subtitle: "\(best.region) · \(ZFormat.latency(best.latencyMs))", payload: String(best.id)))
            }
            out.append(CommandSuggestion(kind: .testRule, title: ZL.tr("github.com 走哪条规则？"), subtitle: ZL.tr("测试规则"), payload: "github.com"))
            if state?.mode != .global {
                out.append(CommandSuggestion(kind: .switchMode, title: Self.switchModeTitle(.global), subtitle: nil, payload: ZephyrKit.ProxyMode.global.rawValue))
            }
            let subs = await subscriptionsSummary()
            out.append(CommandSuggestion(kind: .openPage, title: "订阅", subtitle: ZL.s("%@ 个订阅", ZFormat.count(Int64(subs.count))), payload: "subscriptions"))
            return out
        }
        var out: [CommandSuggestion] = []

        if Self.looksLikeHost(q), let t = try? await testRule(input: q) {
            let layer = t.layerIndex.map { ZL.f("第 %lld 层", Int64($0 + 1)) } ?? ZL.tr("其余流量")
            let result: String = switch t.policy {
            case "DIRECT": ZL.tr("直连")
            case "REJECT": ZL.tr("已拦截")
            default: ZL.s("场景 · %@", t.scene?.name ?? t.policy)
            }
            out.append(CommandSuggestion(kind: .testRule, title: ZL.s("测试规则 %@", t.input), subtitle: "\(layer) → \(result)", payload: t.input))
        }

        // 触发规则见 CommandMatch（#1 A 2026-11-22 20:43）：执行类整词或前缀 ≥ 2，导航类子串；标题（含译文）与别名都算。
        for m in Self.commandModes where CommandMatch.action(q, names: m.2 + [Self.switchModeTitle(m.1)]) {
            out.append(CommandSuggestion(kind: .switchMode, title: Self.switchModeTitle(m.1), subtitle: nil, payload: m.1.rawValue))
        }
        if CommandMatch.action(q, names: CommandMatch.toggleAliases + [toggle.title]) { out.append(toggle) }

        if !Self.looksLikeHost(q), let r = try? await queryNodes(query: q), r.total > 0, !r.highlights.isEmpty {
            out.append(CommandSuggestion(kind: .openNodeQuery, title: ZL.s("在节点库中查找“%@”", raw),
                                         subtitle: ZL.s("%@ 个节点", ZFormat.count(r.total)), payload: q))
            if let best = await fastest(query: q) {
                out.append(CommandSuggestion(kind: .switchNode, title: ZL.s("切到 %@", best.name),
                                             subtitle: "\(best.region) · \(ZFormat.latency(best.latencyMs))", payload: String(best.id)))
            }
        }

        for p in Self.commandPages where CommandMatch.navigation(q, names: p.2 + [ZL.tr(p.0)]) {
            out.append(CommandSuggestion(kind: .openPage, title: ZL.tr(p.0), subtitle: nil, payload: p.1))
        }
        return Array(out.prefix(8))
    }
}

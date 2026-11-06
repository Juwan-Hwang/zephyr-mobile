// 命令搜索（契约 §9 mock 规则）：
// 像域名/IP → test_rule；匹配地区/城市/运营商/标签 → open_node_query + 最快节点 switch_node；
// "全局/规则/直连" → switch_mode；页面名 → open_page；"连接/断开" → toggle_connection。≤ 8 条。

import Foundation
import ZephyrKit

enum MockCommands {

    static let modes: [(String, ProxyMode, [String])] = [
        ("全局", .global, ["全局", "global"]), ("规则", .rule, ["规则", "rule"]), ("直连", .direct, ["直连", "direct"]),
    ]
    static let pages: [(String, String, [String])] = [
        ("节点", "nodes", ["节点", "nodes", "node"]), ("订阅", "subscriptions", ["订阅", "sub", "subscriptions"]),
        ("规则", "rules", ["规则", "rules"]), ("场景", "scenes", ["场景", "scene"]), ("设置", "settings", ["设置", "settings"]),
        ("连接", "connections", ["连接列表", "connections"]), ("日志", "logs", ["日志", "logs", "log"]), ("今日", "today", ["今日", "today"]),
    ]

    static func looksLikeHost(_ q: String) -> Bool {
        guard !q.contains(where: { $0.isWhitespace }), q.count >= 3 else { return false }
        if MockRules.isIPv4(q) || MockRules.isIPv6(q) { return true }
        let labels = q.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return labels.last!.allSatisfy { $0.isLetter } && q.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    static func suggest(input: String, engine: MockEngine) async -> [CommandSuggestion] {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = engine.withState { $0.connection.status }
        let on = status == .connected || status == .connecting
        let toggle = CommandSuggestion(kind: .toggleConnection, title: on ? "断开连接" : "连接",
                                       subtitle: on ? "当前已连接" : "当前未连接", payload: on ? "disconnect" : "connect")
        if q.isEmpty {
            return [
                toggle,
                CommandSuggestion(kind: .switchNode, title: "AI 切到东京 03", subtitle: "JP · 61 ms",
                                  payload: String(MockFixtures.tk03.summary.id)),
                CommandSuggestion(kind: .openNodeQuery, title: "日本 IPLC 节点", subtitle: "在节点库中查找", payload: "日本 iplc"),
                CommandSuggestion(kind: .testRule, title: "github.com 走哪条规则？", subtitle: "测试规则", payload: "github.com"),
                CommandSuggestion(kind: .switchMode, title: "切换到全局模式", subtitle: "出口：东京 03", payload: ProxyMode.global.rawValue),
                CommandSuggestion(kind: .openPage, title: "订阅", subtitle: "214 个订阅", payload: "subscriptions"),
            ]
        }
        var out: [CommandSuggestion] = []

        if looksLikeHost(q), let t = try? await engine.testRule(input: q) {
            let layer = t.layerIndex.map { "第 \($0 + 1) 层" } ?? "第 8 层 · 其余流量"
            let result: String
            switch t.policy {
            case "DIRECT": result = "直连"
            case "REJECT": result = "已拦截"
            default: result = "场景 · \(t.scene?.name ?? t.policy)"
            }
            out.append(CommandSuggestion(kind: .testRule, title: "测试规则 \(t.input)", subtitle: "\(layer) → \(result)", payload: t.input))
        }

        for m in modes where m.2.contains(q) || m.2.contains(where: { $0.hasPrefix(q) && q.count >= 2 }) {
            out.append(CommandSuggestion(kind: .switchMode, title: "切换到\(m.0)模式", subtitle: nil, payload: m.1.rawValue))
        }

        if ["连接", "断开", "connect", "disconnect", "开", "关"].contains(q) { out.append(toggle) }

        let model = MockQuery.build(q)
        if !model.highlights.isEmpty && model.total > 0 {
            out.append(CommandSuggestion(kind: .openNodeQuery, title: "在节点库中查找“\(input.trimmingCharacters(in: .whitespaces))”",
                                         subtitle: "\(ZFormat.count(model.total)) 个节点", payload: q))
            if let best = fastest(model: model, engine: engine) {
                out.append(CommandSuggestion(kind: .switchNode, title: "切到 \(best.name)",
                                             subtitle: "\(best.region) · \(ZFormat.latency(best.latencyMs))", payload: String(best.id)))
            }
        }

        for p in pages where p.2.contains(q) {
            out.append(CommandSuggestion(kind: .openPage, title: p.0, subtitle: nil, payload: p.1))
        }
        return Array(out.prefix(8))
    }

    /// 最快节点：先看具名节点（场景池），否则在结果前 500 个里取最小缓存延迟。不扫全表。
    static func fastest(model: MockQueryModel, engine: MockEngine) -> NodeSummary? {
        let codes = Set(model.groups.map { MockNodes.regions[$0.region].code })
        let pinned = MockFixtures.pinned.map(\.summary).filter { s in
            codes.contains(s.region) && model.highlights.allSatisfy { h in
                s.name.lowercased().contains(h.lowercased()) || MockNodes.regions.contains { $0.code == s.region && ($0.code.lowercased() == h || $0.name == h) }
            }
        }
        if let p = pinned.min(by: { ($0.latencyMs ?? .max) < ($1.latencyMs ?? .max) }) { return p }
        let page = engine.rows(model: model, offset: 0, limit: 500)
        return page.rows.filter { ($0.latencyMs ?? -1) >= 0 }.min { $0.latencyMs! < $1.latencyMs! } ?? page.rows.first
    }
}

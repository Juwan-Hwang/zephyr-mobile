// 命令搜索（契约 §9）的真实实现：规则走 Rust 规则引擎、节点查询与最快节点走 mmap 节点库，≤ 8 条。
// 规则与 Mock 一致：像域名/IP → test_rule；"全局/规则/直连" → switch_mode；"连接/断开" → toggle_connection；
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
        ("连接", "connections", ["连接列表", "connections"]), ("日志", "logs", ["日志", "logs", "log"]), ("今日", "today", ["今日", "today"]),
    ]

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
        let toggle = CommandSuggestion(kind: .toggleConnection, title: on ? "断开连接" : "连接",
                                       subtitle: on ? "当前已连接" : "当前未连接", payload: on ? "disconnect" : "connect")
        if q.isEmpty {
            var out = [toggle]
            if let best = await fastest(query: "") {
                out.append(CommandSuggestion(kind: .switchNode, title: "切到 \(best.name)",
                                             subtitle: "\(best.region) · \(ZFormat.latency(best.latencyMs))", payload: String(best.id)))
            }
            out.append(CommandSuggestion(kind: .testRule, title: "github.com 走哪条规则？", subtitle: "测试规则", payload: "github.com"))
            if state?.mode != .global {
                out.append(CommandSuggestion(kind: .switchMode, title: "切换到全局模式", subtitle: nil, payload: ZephyrKit.ProxyMode.global.rawValue))
            }
            let subs = await subscriptionsSummary()
            out.append(CommandSuggestion(kind: .openPage, title: "订阅", subtitle: "\(subs.count) 个订阅", payload: "subscriptions"))
            return out
        }
        var out: [CommandSuggestion] = []

        if Self.looksLikeHost(q), let t = try? await testRule(input: q) {
            let layer = t.layerIndex.map { "第 \($0 + 1) 层" } ?? "其余流量"
            let result: String = switch t.policy {
            case "DIRECT": "直连"
            case "REJECT": "已拦截"
            default: "场景 · \(t.scene?.name ?? t.policy)"
            }
            out.append(CommandSuggestion(kind: .testRule, title: "测试规则 \(t.input)", subtitle: "\(layer) → \(result)", payload: t.input))
        }

        for m in Self.commandModes where m.2.contains(q) || m.2.contains(where: { $0.hasPrefix(q) && q.count >= 2 }) {
            out.append(CommandSuggestion(kind: .switchMode, title: "切换到\(m.0)模式", subtitle: nil, payload: m.1.rawValue))
        }
        if ["连接", "断开", "connect", "disconnect", "开", "关"].contains(q) { out.append(toggle) }

        if !Self.looksLikeHost(q), let r = try? await queryNodes(query: q), r.total > 0, !r.highlights.isEmpty {
            out.append(CommandSuggestion(kind: .openNodeQuery, title: "在节点库中查找“\(raw)”",
                                         subtitle: "\(ZFormat.count(r.total)) 个节点", payload: q))
            if let best = await fastest(query: q) {
                out.append(CommandSuggestion(kind: .switchNode, title: "切到 \(best.name)",
                                             subtitle: "\(best.region) · \(ZFormat.latency(best.latencyMs))", payload: String(best.id)))
            }
        }

        for p in Self.commandPages where p.2.contains(q) {
            out.append(CommandSuggestion(kind: .openPage, title: p.0, subtitle: nil, payload: p.1))
        }
        return Array(out.prefix(8))
    }
}

// 规则 —— 移植原型 LAYERS / matchRule（contract/mock-spec.md §4）。
// 7 条正则按顺序手写为 O(len) 的字符串判断（不依赖 Regex，Linux/iOS 行为一致）。

import Foundation
import ZephyrKit

enum MockRules {

    /// (kind, name, count, note)
    static let layers: [(LayerKind, String, Int64, String)] = [
        (.override, "Zephyr 覆写", 14, "在订阅之上"),
        (.subscription, "Nebula Cloud", 1284, "订阅规则"),
        (.domain, "OpenAI", 312, "规则集 · 每天更新"),
        (.domain, "广告与跟踪", 61_204_113, "规则集 · 每天更新"),
        (.domain, "威胁情报", 33_481_790, "规则集 · 每小时更新"),
        (.domain, "geosite:cn", 8_912_004, "规则集 · 每周更新"),
        (.ip, "geoip:cn", 7214, "规则集 · 每周更新"),
    ]
    /// 103,606,731
    static let total: Int64 = layers.reduce(0) { $0 + $1.2 }
    /// "磁盘占用 1.9 GB"
    static let diskBytes: Int64 = 1_900_000_000

    struct Hit: Equatable {
        var layer: Int
        var rule: String
        var ruleNo: Int64
        /// 原型代号：DIRECT | REJECT | AI | V | O
        var policy: String
    }

    /// 原型代号 → 契约 policy（场景 id 或 DIRECT/REJECT）。
    static func contractPolicy(_ p: String) -> String {
        switch p { case "AI": "ai"; case "V": "video"; case "O": "other"; default: p }
    }

    // MARK: 判断函数（与原型正则逐条对应）

    /// /(^|\.)name$/
    private static func suffix(_ q: String, _ name: String) -> Bool { q == name || q.hasSuffix("." + name) }

    /// /^\d+\.\d+\.\d+\.\d+$/（ASCII 数字）
    static func isIPv4(_ q: String) -> Bool {
        let parts = q.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in !p.isEmpty && p.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" } }
    }

    static func isIPv6(_ q: String) -> Bool {
        q.contains(":") && q.unicodeScalars.allSatisfy { $0 == ":" || $0 == "." || ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") }
    }

    private static func lastTwoLabels(_ q: String) -> String {
        q.split(separator: ".", omittingEmptySubsequences: false).suffix(2).joined(separator: ".")
    }

    /// /doubleclick|adservice|(^|\.)ads?\.|tracker|analytics/
    private static func adHit(_ q: String) -> Bool {
        if q.contains("doubleclick") || q.contains("adservice") || q.contains("tracker") || q.contains("analytics") { return true }
        if q.hasPrefix("ad.") || q.hasPrefix("ads.") || q.contains(".ad.") || q.contains(".ads.") { return true }
        return false
    }

    /// q.match(/doubleclick|adservice|ads?|tracker|analytics/)[0]：最左位置，同位置按备选顺序。
    private static func adKeyword(_ q: String) -> String {
        let u = Array(q.unicodeScalars)
        func at(_ i: Int, _ w: String) -> Bool {
            let ws = Array(w.unicodeScalars)
            guard i + ws.count <= u.count else { return false }
            for k in 0..<ws.count where u[i + k] != ws[k] { return false }
            return true
        }
        for i in 0..<u.count {
            if at(i, "doubleclick") { return "doubleclick" }
            if at(i, "adservice") { return "adservice" }
            if at(i, "ads") { return "ads" }
            if at(i, "ad") { return "ad" }
            if at(i, "tracker") { return "tracker" }
            if at(i, "analytics") { return "analytics" }
        }
        return "ad"
    }

    private static let cnIpPrefixes = ["1.0.", "36.", "58.", "101.", "110.", "111.", "112.", "113.", "114.", "115.", "116.",
                                       "117.", "118.", "119.", "120.", "121.", "122.", "123.", "124.", "125."]

    /// 返回规范化输入（trim + lowercase）、是否 IP、命中。空输入返回 nil。
    static func match(_ input: String) -> (q: String, isIp: Bool, hit: Hit?)? {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return nil }
        let v4 = isIPv4(q)
        let ip = v4 || isIPv6(q)
        if ip {
            if v4, cnIpPrefixes.contains(where: { q.hasPrefix($0) }) {
                let two = q.split(separator: ".").prefix(2).joined(separator: ".")
                return (q, true, Hit(layer: 6, rule: "IP-CIDR,\(two).0.0/16", ruleNo: 3302, policy: "DIRECT"))
            }
            return (q, true, nil)
        }
        if suffix(q, "github.com") {
            return (q, false, Hit(layer: 0, rule: "DOMAIN-SUFFIX,github.com", ruleNo: 2, policy: "DIRECT"))
        }
        if suffix(q, "netflix.com") || suffix(q, "nflxvideo.net") {
            return (q, false, Hit(layer: 1, rule: "DOMAIN-SUFFIX,netflix.com", ruleNo: 318, policy: "V"))
        }
        if ["openai.com", "chatgpt.com", "claude.ai", "anthropic.com"].contains(where: { suffix(q, $0) }) {
            return (q, false, Hit(layer: 2, rule: "DOMAIN-SUFFIX," + lastTwoLabels(q), ruleNo: 41, policy: "AI"))
        }
        if adHit(q) {
            return (q, false, Hit(layer: 3, rule: "DOMAIN-KEYWORD," + adKeyword(q), ruleNo: 18_204_451, policy: "REJECT"))
        }
        if q.contains("malware") || q.contains("phish") {
            return (q, false, Hit(layer: 4, rule: "DOMAIN," + q, ruleNo: 2_201_833, policy: "REJECT"))
        }
        if ["baidu", "qq", "taobao", "bilibili", "weibo", "jd"].contains(where: { suffix(q, $0 + ".com") }) || q.hasSuffix(".cn") {
            return (q, false, Hit(layer: 5, rule: "DOMAIN-SUFFIX," + lastTwoLabels(q), ruleNo: 1_120_458, policy: "DIRECT"))
        }
        return (q, false, nil)
    }
}

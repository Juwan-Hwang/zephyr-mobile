// 导入载荷解析（契约 §15，REVIEW-Q2 X-P1-11）：二维码 / 剪贴板里的字符串 → 待导入的订阅列表。
//
// 真引擎直接用核心的 parseImportPayload；这里是同一规则的 Swift 实现，供 MockEngine 与 UI 预解析
// （扫码即时提示、多条确认）使用。两边以 contract/fixtures/import-payload-v1.json 为准，单测逐条比对。
//
// 接受（scheme / host 大小写不敏感，载荷 ≤ 4096 字节，最多 20 条）：
//   1. zephyr://import?url=<pct>&name=<pct>&auto=<小时>      桌面"同步到手机"单条
//   2. zephyr://import?v=1&d=<base64url 无填充(JSON)>         多条，JSON = {"v":1,"subs":[{"name","url","auto"}]}
//   3. clash:// | clashmeta:// | mihomo://install-config?url=…&name=…
//   4. 裸 http(s):// 链接

import Foundation

public struct ParsedImport: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case zephyr, clashInstall, url }

    public struct Item: Sendable, Hashable {
        public var name: String?
        public var url: String
        public var autoUpdateHours: Int32?
        public init(name: String?, url: String, autoUpdateHours: Int32?) {
            self.name = name; self.url = url; self.autoUpdateHours = autoUpdateHours
        }
    }

    /// 与核心 MobileError 的两个类别对应（Invalid / SubscriptionInvalid）。
    public enum Failure: Error, Sendable, Hashable {
        case invalid(String)
        case subscriptionInvalid(String)

        public var category: String {
            switch self { case .invalid: "invalid"; case .subscriptionInvalid: "subscription_invalid" }
        }
        public var message: String {
            switch self { case .invalid(let m), .subscriptionInvalid(let m): m }
        }
    }

    public static let maxItems = 20
    public static let maxPayloadBytes = 4096

    public var kind: Kind
    public var items: [Item]

    public init(kind: Kind, items: [Item]) { self.kind = kind; self.items = items }

    /// 解析；失败抛 `Failure`。
    public static func parse(_ payload: String) throws -> ParsedImport {
        let p = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw Failure.invalid("空载荷") }
        guard p.utf8.count <= maxPayloadBytes else { throw Failure.invalid("载荷过长") }

        let out: ParsedImport
        if let q = query(after: ["zephyr://import"], in: p) {
            out = ParsedImport(kind: .zephyr, items: try zephyr(q))
        } else if let q = query(after: ["clash://install-config", "clashmeta://install-config", "mihomo://install-config"], in: p) {
            out = ParsedImport(kind: .clashInstall, items: [try item(from: try pairs(q))])
        } else if p.lowercased().hasPrefix("http://") || p.lowercased().hasPrefix("https://") {
            out = ParsedImport(kind: .url, items: [try finish(name: nil, url: p, auto: nil)])
        } else {
            throw Failure.invalid("不是订阅链接或 Zephyr 导入码")
        }
        guard !out.items.isEmpty else { throw Failure.invalid("载荷里没有订阅") }
        guard out.items.count <= maxItems else { throw Failure.invalid("一次最多导入 \(maxItems) 个订阅") }
        return out
    }

    /// 与引擎错误对齐的便捷版本（UI / Mock 用）。
    public static func parseOrThrowEngineError(_ payload: String) throws -> ParsedImport {
        do { return try parse(payload) } catch let f as Failure {
            throw ZephyrError(code: .subscriptionInvalid, message: f.message)
        }
    }

    /// 看起来是整份 Clash / mihomo 配置（剪贴板直接粘 YAML）。
    public static func looksLikeConfig(_ payload: String) -> Bool {
        payload.contains("proxies:") || payload.contains("proxy-providers:")
    }

    // MARK: 内部

    /// 前缀匹配（大小写不敏感）→ `?` 之后、`#` 之前的查询串；前缀后无内容返回 ""，后面不是 `?` 返回 nil。
    private static func query(after prefixes: [String], in p: String) -> String? {
        let lower = p.lowercased()
        for pre in prefixes where lower.hasPrefix(pre) {
            var rest = p.dropFirst(pre.count)
            if rest.hasPrefix("/") { rest = rest.dropFirst() }
            if rest.isEmpty { return "" }
            guard rest.hasPrefix("?") else { return nil }
            return String(rest.dropFirst().split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        }
        return nil
    }

    private static func pairs(_ q: String) throws -> [(String, String)] {
        try q.split(separator: "&").filter { !$0.isEmpty }.map { kv in
            let parts = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (try pct(String(parts[0])), try pct(parts.count > 1 ? String(parts[1]) : ""))
        }
    }

    private static func get(_ pairs: [(String, String)], _ key: String) -> String? {
        pairs.first { $0.0 == key }?.1
    }

    private struct Batch: Decodable {
        struct Sub: Decodable { var name: String?; var url: String; var auto: Int32? }
        var v: UInt32
        var subs: [Sub]
    }

    private static func zephyr(_ q: String) throws -> [Item] {
        let ps = try pairs(q)
        if let v = get(ps, "v"), v != "1" { throw Failure.invalid("导入码版本 v\(v) 过新，请更新 Zephyr") }
        if let d = get(ps, "d") {
            guard let raw = base64URL(d), let batch = try? JSONDecoder().decode(Batch.self, from: raw) else {
                throw Failure.invalid("导入码数据损坏")
            }
            guard batch.v == 1 else { throw Failure.invalid("导入码版本 v\(batch.v) 过新，请更新 Zephyr") }
            return try batch.subs.map { try finish(name: $0.name, url: $0.url, auto: $0.auto) }
        }
        return [try item(from: ps)]
    }

    private static func item(from ps: [(String, String)]) throws -> Item {
        guard let url = get(ps, "url") else { throw Failure.invalid("缺少 url") }
        var auto: Int32?
        if let a = get(ps, "auto"), !a.isEmpty {
            guard let n = Int32(a) else { throw Failure.invalid("auto 不是整数") }
            auto = n
        }
        return try finish(name: get(ps, "name"), url: url, auto: auto)
    }

    private static func finish(name: String?, url: String, auto: Int32?) throws -> Item {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateURL(url)
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = auto, !(0...720).contains(a) { throw Failure.invalid("auto 超出范围（0–720 小时）") }
        return Item(name: (name?.isEmpty ?? true) ? nil : name, url: url, autoUpdateHours: auto)
    }

    /// 桌面 validate_subscription_url_basic 的要点：仅 http/https、恰好 `//` 后跟主机、无控制字符。
    private static func validateURL(_ url: String) throws {
        if url.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            throw Failure.subscriptionInvalid("Invalid URL: must not contain control characters")
        }
        let lower = url.lowercased()
        guard let rest = lower.hasPrefix("https://") ? lower.dropFirst(8) : lower.hasPrefix("http://") ? lower.dropFirst(7) : nil else {
            throw Failure.subscriptionInvalid("Invalid URL: only http and https are allowed")
        }
        guard !rest.hasPrefix("/"), let c = URLComponents(string: url), let host = c.host, !host.isEmpty else {
            throw Failure.subscriptionInvalid("Invalid URL: missing host")
        }
    }

    /// 百分号解码（`+` 视为空格，与核心一致）；坏编码报错。
    private static func pct(_ s: String) throws -> String {
        var out: [UInt8] = []
        let b = Array(s.utf8)
        var i = 0
        while i < b.count {
            switch b[i] {
            case UInt8(ascii: "%"):
                guard i + 2 < b.count, let v = UInt8(String(decoding: b[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) else {
                    throw Failure.invalid("百分号编码错误")
                }
                out.append(v); i += 3
            case UInt8(ascii: "+"):
                out.append(UInt8(ascii: " ")); i += 1
            default:
                out.append(b[i]); i += 1
            }
        }
        guard let str = String(bytes: out, encoding: .utf8) else { throw Failure.invalid("不是 UTF-8") }
        return str
    }

    private static func base64URL(_ s: String) -> Data? {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        t = t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

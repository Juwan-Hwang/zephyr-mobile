// NodeNameMarkup — 节点名称的高亮区间与倍率后缀拆分（纯 Swift，可单测）。
//
// 与原型 mark() 一致：每个高亮词在名称里取第一次出现（大小写不敏感）着强调色；
// 名称末尾的 " ×1.5" 拆为小号等宽灰字。

import Foundation

struct NodeNameMarkup: Equatable, Sendable {
    /// 去掉倍率后缀后的主体名称
    var base: String
    /// 倍率文本，如 "×1.5"；没有则为 nil
    var multiplier: String?
    /// base 内需要高亮的 UTF-16 区间（NSRange 语义：location, length），按位置排序、互不重叠
    var highlights: [Range<Int>]

    init(name: String, highlights terms: [String]) {
        let (b, m) = Self.splitMultiplier(name)
        base = b
        multiplier = m
        highlights = Self.ranges(in: b, terms: terms)
    }

    static func splitMultiplier(_ name: String) -> (String, String?) {
        // 末尾形如 " ×1.5" / " ×2"
        guard let x = name.range(of: " ×", options: .backwards) else { return (name, nil) }
        let tail = name[x.upperBound...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isNumber || $0 == "." }) else { return (name, nil) }
        return (String(name[..<x.lowerBound]), "×" + tail)
    }

    static func ranges(in text: String, terms: [String]) -> [Range<Int>] {
        guard !terms.isEmpty, !text.isEmpty else { return [] }
        let ns = text as NSString
        var found: [Range<Int>] = []
        for t in terms where !t.isEmpty {
            let r = ns.range(of: t, options: [.caseInsensitive])
            guard r.location != NSNotFound else { continue }
            let rr = r.location..<(r.location + r.length)
            if !found.contains(where: { $0.overlaps(rr) }) { found.append(rr) }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}

/// 中文紧凑计数：312 万 / 1,311 万 / 1.04 亿（原型 chips 与资料库卡片）。
enum CompactCount {
    /// 千分位分组（不依赖 NumberFormatter，热路径零分配开销小）。
    static func grouped(_ v: Int64) -> String {
        let neg = v < 0
        var digits = Array(String(neg ? -v : v))
        var out: [Character] = []
        out.reserveCapacity(digits.count + digits.count / 3)
        while digits.count > 3 {
            out.insert(contentsOf: digits.suffix(3), at: 0)
            out.insert(",", at: 0)
            digits.removeLast(3)
        }
        out.insert(contentsOf: digits, at: 0)
        return (neg ? "-" : "") + String(out)
    }

    static func zh(_ n: Int64) -> String {
        if n < 100_000 { return grouped(n) }
        if n < 100_000_000 {
            return grouped(Int64((Double(n) / 10_000).rounded())) + " 万"
        }
        let yi = Double(n) / 100_000_000
        return String(format: "%.2f 亿", yi)
    }

    /// chips 用："312 万"（原型 (count/1e4).toFixed(0)），不足 1 万时显示原数。
    static func chip(_ n: Int64) -> String {
        n < 10_000 ? zh(n) : "\(Int64((Double(n) / 10_000).rounded())) 万"
    }
}

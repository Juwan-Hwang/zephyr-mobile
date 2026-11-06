// queryNodes —— 移植原型 buildModel / rowAt（contract/mock-spec.md §3）。
// 每个地区只在一个周期 P（≤ 5·L·C ≤ 100）内筛余数，命中数用闭式求和：O(地区数 × P)，绝不扫全表。

import ZephyrKit

/// 一个地区的命中描述：分区内第 k 个节点的 j = (k / S.count) * P + S[k % S.count]。
public struct MockGroup: Sendable, Hashable {
    public let region: Int
    public let count: Int64
    let residues: [Int64]
    let period: Int64

    @inline(__always) public func index(at k: Int64) -> Int64 {
        let n = Int64(residues.count)
        return (k / n) * period + residues[Int(k % n)]
    }
}

public struct MockQueryModel: Sendable, Hashable {
    public let query: String
    public let groups: [MockGroup]
    public let highlights: [String]
    /// 每个分区之前的节点数（不含头行），用于 offset → 分区二分。
    let nodeStarts: [Int64]
    public let total: Int64

    /// 契约 RegionSection：rowOffset 含分区头行。
    public var sections: [RegionSection] {
        var out: [RegionSection] = []
        out.reserveCapacity(groups.count)
        var row: Int64 = 0
        for g in groups {
            let reg = MockNodes.regions[g.region]
            out.append(RegionSection(region: reg.code, name: reg.name, count: g.count, rowOffset: row))
            row += 1 + g.count
        }
        return out
    }

    /// 节点序号（不含头行）→ (分区, 分区内序号)。
    @inline(__always) func locate(ordinal: Int64) -> (group: Int, k: Int64)? {
        guard ordinal >= 0, ordinal < total, !groups.isEmpty else { return nil }
        var lo = 0, hi = groups.count - 1
        while lo < hi {
            let m = (lo + hi + 1) >> 1
            if nodeStarts[m] <= ordinal { lo = m } else { hi = m - 1 }
        }
        return (lo, ordinal - nodeStarts[lo])
    }

    /// 节点序号 → (region, j)。
    public func node(ordinal: Int64) -> (r: Int, j: Int64)? {
        guard let (gi, k) = locate(ordinal: ordinal) else { return nil }
        let g = groups[gi]
        return (g.region, g.index(at: k))
    }

    /// 虚拟列表行号（含头行）→ 头行 / (region, j)。与原型 rowAt 一致。
    public func row(_ row: Int64) -> (header: Bool, region: Int, j: Int64)? {
        guard let loc = sections.locate(row: row) else { return nil }
        switch loc {
        case .header(let s): return (true, groups[s].region, -1)
        case .node(let s, let k, _): return (false, groups[s].region, groups[s].index(at: k))
        }
    }
}

enum MockQuery {

    private static func isTypingToken(_ tk: String) -> Bool {
        // /^[a-z0-9+-]{1,3}$/
        let u = Array(tk.unicodeScalars)
        guard (1...3).contains(u.count) else { return false }
        return u.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "+" || c == "-"
        }
    }

    /// JS `\s` 的近似：Unicode 空白。
    private static func tokens(_ q: String) -> [String] {
        q.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func build(_ q: String) -> MockQueryModel {
        let regions = MockNodes.regions
        let toks = tokens(q)
        var regs: Set<Int>? = nil
        var cityTok: [Int: Int]? = nil
        var tag: Int? = nil
        var car: [Int: Int]? = nil
        var ok = true
        var hl: [String] = []
        func meet(_ s: Set<Int>) { regs = regs.map { $0.intersection(s) } ?? s }

        for (ti, tk) in toks.enumerated() {
            let last = ti == toks.count - 1
            var s = Set<Int>()
            // a. 地区
            for (ri, g) in regions.enumerated()
            where g.code.lowercased() == tk || g.name.contains(tk) || tk.contains(g.name) { s.insert(ri) }
            if !s.isEmpty { meet(s); hl.append(tk); continue }
            // b. 城市
            for (ri, g) in regions.enumerated() {
                for (ci, c) in g.cities.enumerated() where c.contains(tk) || tk.contains(c) {
                    s.insert(ri)
                    if cityTok == nil { cityTok = [:] }
                    cityTok![ri] = ci
                    hl.append(c)
                }
            }
            if !s.isEmpty { meet(s); continue }
            // c. 运营商
            let tkLen = tk.utf16.count
            for (ri, g) in regions.enumerated() {
                let ci = g.carriers.firstIndex { x in
                    let l = x.lowercased()
                    return l == tk
                        || l.filter { !$0.isWhitespace } == tk
                        || l.split(whereSeparator: { $0.isWhitespace }).contains { String($0) == tk }
                        || (tkLen >= 2 && l.hasPrefix(tk))
                }
                if let ci {
                    s.insert(ri)
                    if car == nil { car = [:] }
                    car![ri] = ci
                    hl.append(g.carriers[ci])
                }
            }
            if !s.isEmpty { meet(s); continue }
            // d. 标签
            if let t = MockNodes.tags.firstIndex(where: { x in
                let l = x.lowercased(); return l == tk || (tkLen >= 2 && l.hasPrefix(tk))
            }) {
                tag = t; hl.append(MockNodes.tags[t]); continue
            }
            // e. 打字中
            if last && isTypingToken(tk) { continue }
            ok = false
        }

        var groups: [MockGroup] = []
        if ok {
            for (ri, g) in regions.enumerated() {
                if let regs, !regs.contains(ri) { continue }
                let L = Int64(g.cities.count), C = Int64(g.carriers.count)
                let hasC = car?[ri] != nil, hasT = cityTok?[ri] != nil
                var P = (hasT ? L : 1) * ((tag != nil || hasC) ? 5 : 1) * (hasC ? C : 1)
                if P == 0 { P = 1 }
                var S: [Int64] = []
                for j in 0..<P {
                    if let ct = cityTok?[ri], j % L != Int64(ct) { continue }
                    if let tag, MockNodes.tagOf(ri, j) != tag { continue }
                    if let cr = car?[ri], MockNodes.carOf(ri, j) != cr { continue }
                    S.append(j)
                }
                var cnt: Int64 = 0
                for s in S where s < g.count { cnt += (g.count - 1 - s) / P + 1 }
                if cnt > 0 { groups.append(MockGroup(region: ri, count: cnt, residues: S, period: P)) }
            }
        }
        var starts: [Int64] = []
        var acc: Int64 = 0
        for g in groups { starts.append(acc); acc += g.count }
        return MockQueryModel(query: q, groups: groups, highlights: hl, nodeStarts: starts, total: acc)
    }
}

// NodeRowMap — 逻辑行 ↔（分区, 节点序号）映射（纯 Swift，可单测）。
//
// 契约 §5：虚拟列表总行数 = total + sections.count（每个分区一行头）。
// 行号 → 分区用二分；节点序号（nodeRows 的 offset，不含头行）= row - (分区下标 + 1)。
// rowOffset 本地按 count 重新累加，不依赖引擎给的 rowOffset 语义细节。

import Foundation

struct NodeRowMap: Equatable, Sendable {
    struct Section: Equatable, Sendable {
        var region: String     // "US"
        var name: String       // "美国"
        var count: Int64       // 该分区节点数
        var headerRow: Int64   // 头行所在的逻辑行
        /// 该分区第一个节点在整个结果中的序号（0 基，不含头行）
        var firstOrdinal: Int64
    }

    enum Row: Equatable, Sendable {
        case header(section: Int)
        /// ordinal：结果内节点序号（0 基，nodeRows 的 offset）；indexInSection：分区内序号（0 基）
        case node(section: Int, ordinal: Int64, indexInSection: Int64)
    }

    let sections: [Section]
    let totalNodes: Int64

    init(sections raw: [(region: String, name: String, count: Int64)]) {
        var out: [Section] = []
        out.reserveCapacity(raw.count)
        var row: Int64 = 0, ordinal: Int64 = 0
        for s in raw where s.count > 0 {
            out.append(Section(region: s.region, name: s.name, count: s.count, headerRow: row, firstOrdinal: ordinal))
            row += s.count + 1
            ordinal += s.count
        }
        sections = out
        totalNodes = ordinal
    }

    static let empty = NodeRowMap(sections: [])

    var rowCount: Int64 { totalNodes + Int64(sections.count) }
    var isEmpty: Bool { totalNodes == 0 }

    /// 某逻辑行所属分区（二分，O(log 分区数)）。
    func sectionIndex(forRow row: Int64) -> Int {
        guard !sections.isEmpty else { return 0 }
        var lo = 0, hi = sections.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if sections[mid].headerRow <= row { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func row(at row: Int64) -> Row {
        let s = sectionIndex(forRow: row)
        let sec = sections[s]
        if row == sec.headerRow { return .header(section: s) }
        let idx = row - sec.headerRow - 1
        return .node(section: s, ordinal: sec.firstOrdinal + idx, indexInSection: idx)
    }

    /// 节点序号 → 逻辑行。
    func logicalRow(forOrdinal ordinal: Int64) -> Int64 {
        guard !sections.isEmpty else { return 0 }
        var lo = 0, hi = sections.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if sections[mid].firstOrdinal <= ordinal { lo = mid } else { hi = mid - 1 }
        }
        return ordinal + Int64(lo) + 1
    }

    /// 视口顶部第一个节点行的 1 基序号（底部“n / total”）。顶部是头行时取其后第一个节点。
    func displayOrdinal(firstVisibleRow row: Int64) -> Int64 {
        guard !isEmpty else { return 0 }
        switch self.row(at: row) {
        case .header(let s): return sections[s].firstOrdinal + 1
        case .node(_, let ordinal, _): return ordinal + 1
        }
    }

    /// 索引条：竖向比例 f ∈ [0,1) → 目标行（先等分到分区，再按分区内比例），与原型 railAt 一致。
    func railTarget(fraction f: Double) -> (section: Int, row: Int64, indexInSection: Int64)? {
        guard !sections.isEmpty else { return nil }
        let clamped = min(0.999_999, max(0, f))
        let scaled = clamped * Double(sections.count)
        let s = min(sections.count - 1, Int(scaled.rounded(.down)))
        let within = scaled - Double(s)
        let sec = sections[s]
        let idx = min(sec.count - 1, Int64((within * Double(sec.count)).rounded(.down)))
        // idx == 0 时落在头行，让分区头可见；其余直接落在节点行。
        let row = idx == 0 ? sec.headerRow : sec.headerRow + 1 + idx
        return (s, row, idx)
    }
}

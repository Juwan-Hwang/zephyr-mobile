// VirtualScrollWindow — 1e8 行虚拟滚动的几何核心（纯 Swift，无 UIKit 依赖，可单测）。
//
// 问题：1e8 行 × 52pt = 5.2e9pt。CGFloat 是 Double 能表示，但 UIScrollView 的 contentSize/bounds
// 最终进入 Core Animation（渲染服务器按 Float32 处理图层几何），2^24 ≈ 1.6e7pt 以上就开始丢整数精度，
// 5e9pt 处 ulp ≈ 512pt —— 行会抖动、错位，甚至无法滚动。
//
// 方案（“滑动窗口 + 重定位”，同 Apple WWDC 2011 StreetScroller 的 recenterIfNecessary）：
//  - 物理内容高度封顶为 `windowRows` 行（默认 4096 行 ≈ 21 万 pt；Float32 在 2^18 处 ulp = 1/64 pt，无可见误差）。
//  - 物理第 i 行 = 逻辑第 `baseRow + i` 行。
//  - 物理偏移靠近窗口上/下 1/4 时，把 baseRow 平移整数 k 行，同时 contentOffset.y -= k × rowHeight。
//    行坐标都是 rowHeight 的整数倍，平移前后屏幕像素完全一致；拖动与惯性减速都不会被打断。
//  - 长距离跳转（索引条、搜索、点 chip）直接重设 baseRow，使目标行落在窗口中部。
//  - 窗口顶端 baseRow == 0、底端 baseRow == rowCount - windowRows 时才是真实边缘，回弹只在真实边缘出现。

import Foundation

struct VirtualScrollWindow: Equatable, Sendable {
    /// 逻辑总行数（含分区头行），可达 1e8 以上。
    private(set) var rowCount: Int64
    /// 固定行高（pt）。默认 52，大字体 66。
    private(set) var rowHeight: Double
    /// 物理窗口最多容纳的行数。
    let windowRows: Int64
    /// 物理第 0 行对应的逻辑行。
    private(set) var baseRow: Int64 = 0

    init(rowCount: Int64, rowHeight: Double, windowRows: Int64 = 4096) {
        precondition(rowHeight > 0 && windowRows > 64)
        self.rowCount = max(0, rowCount)
        self.rowHeight = rowHeight
        self.windowRows = windowRows
    }

    // MARK: 物理尺寸

    /// 物理行数（= UICollectionView 的 numberOfItems）。
    var physicalRowCount: Int { Int(min(rowCount, windowRows)) }
    /// 物理内容高度。
    var contentHeight: Double { Double(physicalRowCount) * rowHeight }
    /// baseRow 可取的最大值。
    var maxBaseRow: Int64 { max(0, rowCount - windowRows) }
    /// 是否真的需要窗口化（行数小于窗口时就是普通列表）。
    var isWindowed: Bool { rowCount > windowRows }

    // MARK: 映射

    func logicalRow(forItem item: Int) -> Int64 { baseRow + Int64(item) }

    func item(forLogicalRow row: Int64) -> Int? {
        let i = row - baseRow
        return (i >= 0 && i < Int64(physicalRowCount)) ? Int(i) : nil
    }

    /// 物理 y → 逻辑偏移（pt，Double；1e8 行时约 5.2e9，Double 精确到 1e-6pt）。
    func virtualOffset(physical y: Double) -> Double { Double(baseRow) * rowHeight + y }

    /// 物理偏移处可见的第一行（逻辑），已夹到合法范围。
    func firstVisibleRow(physical y: Double) -> Int64 {
        guard rowCount > 0 else { return 0 }
        let local = Int64((max(0, y) / rowHeight).rounded(.down))
        return min(rowCount - 1, baseRow + local)
    }

    /// 视口内可见的逻辑行范围（半开区间）。
    func visibleRows(physical y: Double, viewport: Double) -> Range<Int64> {
        guard rowCount > 0 else { return 0..<0 }
        let first = firstVisibleRow(physical: y)
        let lastLocal = Int64(((max(0, y) + max(0, viewport)) / rowHeight).rounded(.up))
        let last = min(rowCount, baseRow + lastLocal)
        return first..<max(first, last)
    }

    // MARK: 重定位

    /// 若物理偏移进入窗口两端 1/4 区域，平移 baseRow。返回平移的行数 k（调用方 contentOffset.y -= k × rowHeight，然后重载可见项）。
    mutating func recenterIfNeeded(physical y: Double, viewport: Double) -> Int64 {
        guard isWindowed else { return 0 }
        let span = max(rowHeight, contentHeight - viewport)
        let lowEdge = span * 0.25, highEdge = span * 0.75
        guard y < lowEdge || y > highEdge else { return 0 }
        let viewportRows = Int64((viewport / rowHeight).rounded(.up))
        let targetLocal = max(0, (windowRows - viewportRows) / 2)
        let currentLocal = Int64((max(0, y) / rowHeight).rounded(.down))
        let newBase = min(maxBaseRow, max(0, baseRow + currentLocal - targetLocal))
        let k = newBase - baseRow
        baseRow = newBase
        return k
    }

    /// 跳到某逻辑行（置于视口顶部），返回新的物理偏移。会尽量让目标处于窗口中部。
    mutating func jump(toRow row: Int64, viewport: Double) -> Double {
        guard rowCount > 0 else { baseRow = 0; return 0 }
        let r = min(max(0, row), rowCount - 1)
        if isWindowed {
            baseRow = min(maxBaseRow, max(0, r - windowRows / 2))
        } else {
            baseRow = 0
        }
        let maxPhysical = max(0, contentHeight - viewport)
        return min(maxPhysical, Double(r - baseRow) * rowHeight)
    }

    /// 目标行已在当前窗口且能放到视口顶部时，返回其物理偏移（无需重定位/重载）；否则 nil。
    /// 索引条拖动时绝大多数事件走这条快路径。
    func physicalOffsetInWindow(row: Int64, viewport: Double) -> Double? {
        let local = row - baseRow
        guard local >= 0, local < Int64(physicalRowCount) else { return nil }
        let y = Double(local) * rowHeight
        let maxPhysical = max(0, contentHeight - viewport)
        if y <= maxPhysical { return y }
        // 窗口已贴底（真实底部）时可以夹到底部。
        return baseRow == maxBaseRow ? maxPhysical : nil
    }

    /// 结果集变化（新查询）：重置到顶部。
    mutating func reset(rowCount: Int64) {
        self.rowCount = max(0, rowCount)
        baseRow = 0
    }

    /// 行高变化（Dynamic Type）：保持首行不变，返回新的物理偏移。
    mutating func setRowHeight(_ h: Double, keepingRow row: Int64, viewport: Double) -> Double {
        rowHeight = h
        return jump(toRow: row, viewport: viewport)
    }
}

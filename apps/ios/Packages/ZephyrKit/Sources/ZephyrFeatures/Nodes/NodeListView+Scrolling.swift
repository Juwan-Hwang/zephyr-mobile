// NodeListView + 滚动：窗口重定位、置顶头、底部位置、分页预取、停止滚动 400ms 测速、索引条跳转。

import UIKit
import ZephyrDesign
import ZephyrKit

extension NodeListView {

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isAdjusting else { return }
        recenterIfNeeded()
        let y = collectionView.contentOffset.y
        let dy = y - lastPhysicalY
        if abs(dy) > 0.5 { scrollDirection = dy > 0 ? 1 : -1 }
        lastPhysicalY = y
        updateChrome()
        requestVisiblePages()
        noteScrolled()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { scrollDirection = 0 }

    /// 点状态栏回顶部：物理顶部未必是逻辑顶部，改为自己跳。
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        if scrollWindow.baseRow == 0 { return true }
        jump(toRow: 0)
        return false
    }

    /// 物理偏移进入窗口两端 1/4 时平移 baseRow，并等量回拨 contentOffset。
    /// 行坐标都是 rowHeight 的整数倍，回拨前后同一逻辑行在屏幕上的位置完全一致；
    /// 直接改 contentOffset 不会打断拖动或惯性（Apple StreetScroller 同款做法）。
    func recenterIfNeeded() {
        let y = collectionView.contentOffset.y
        let k = scrollWindow.recenterIfNeeded(physical: Double(y), viewport: Double(viewportHeight))
        guard k != 0 else { return }
        isAdjusting = true
        let newY = y - CGFloat(k) * style.rowHeight
        collectionView.reloadData()   // 物理项 → 逻辑行的映射整体平移了；数据都在缓存里，重配 ~20 个 cell
        collectionView.contentOffset.y = newY
        collectionView.layoutIfNeeded()
        isAdjusting = false
        lastPhysicalY = newY
    }

    // MARK: 置顶头 + 底部

    func updateChrome() {
        guard !rowMap.isEmpty else {
            pinned.isHidden = true
            footer.set(ordinal: 0, total: 0)
            footer.set(tested: store.testedCount)
            return
        }
        let y = Double(collectionView.contentOffset.y)
        let rh = Double(style.rowHeight)
        let first = scrollWindow.firstVisibleRow(physical: y)
        let s = rowMap.sectionIndex(forRow: first)
        let sec = rowMap.sections[s]

        // 原型：vOff > 0.5 行才显示置顶头。
        let showPinned = scrollWindow.virtualOffset(physical: y) > rh * 0.5
        pinned.isHidden = !showPinned
        if showPinned {
            pinned.show(code: sec.region, name: sec.name, count: ZFormat.count(sec.count), style: style)
            // 下一个分区头顶上来时把置顶头推上去。
            var push: CGFloat = 0
            if s + 1 < rowMap.sections.count {
                let nextTop = Double(rowMap.sections[s + 1].headerRow - scrollWindow.baseRow) * rh - y
                let h = Double(NodeListStyle.pinnedHeight)
                if nextTop < h { push = CGFloat(min(0, nextTop - h)) }
            }
            let t = push == 0 ? CGAffineTransform.identity : CGAffineTransform(translationX: 0, y: push)
            if pinned.transform != t { pinned.transform = t }
        }
        footer.set(ordinal: rowMap.displayOrdinal(firstVisibleRow: first), total: rowMap.totalNodes)
        footer.set(tested: store.testedCount)
    }

    // MARK: 分页

    func requestVisiblePages() {
        guard !rowMap.isEmpty else { return }
        let rows = scrollWindow.visibleRows(physical: Double(collectionView.contentOffset.y), viewport: Double(collectionView.bounds.height))
        guard !rows.isEmpty else { return }
        let lo = ordinal(atOrAfter: rows.lowerBound)
        let hi = ordinal(atOrAfter: rows.upperBound - 1) + 1
        store.ensure(ordinals: lo..<max(lo + 1, hi), ahead: scrollDirection)
    }

    /// 行 → 节点序号（头行取其后第一个节点）。
    func ordinal(atOrAfter row: Int64) -> Int64 {
        switch rowMap.row(at: row) {
        case .header(let s): return rowMap.sections[s].firstOrdinal
        case .node(_, let o, _): return o
        }
    }

    // MARK: 停止滚动 400ms → 测可见行

    /// 每次滚动只更新截止时间；最多挂一个延时检查，滚动热路径不分配定时器。
    func noteScrolled() {
        settleDeadline = CACurrentMediaTime() + ZTokens.Motion.settleDelay
        guard !settleScheduled else { return }
        settleScheduled = true
        scheduleSettleCheck(after: ZTokens.Motion.settleDelay)
    }

    private func scheduleSettleCheck(after delay: CFTimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.settleCheck() }
        }
    }

    private func settleCheck() {
        let now = CACurrentMediaTime()
        if now < settleDeadline {
            scheduleSettleCheck(after: settleDeadline - now)
            return
        }
        settleScheduled = false
        settle()
    }

    private func settle() {
        var nodes: [NodeSummary] = []
        let sorted = collectionView.indexPathsForVisibleItems.sorted { $0.item < $1.item }
        for ip in sorted {
            guard case .node(_, let o, _) = rowMap.row(at: scrollWindow.logicalRow(forItem: ip.item)),
                  let n = store.node(atOrdinal: o) else { continue }
            nodes.append(n)
        }
        store.testVisible(nodes)
    }

    // MARK: 索引条

    func railTracked(_ f: Double, phase: NodeIndexRail.Phase, y: CGFloat) {
        guard let t = rowMap.railTarget(fraction: f) else { return }
        if phase != .ended {
            jump(toRow: t.row)
            let sec = rowMap.sections[t.section]
            bubble.set(title: "\(sec.region) \(sec.name)",
                       subtitle: "\(ZFormat.count(t.indexInSection + 1)) / \(ZFormat.count(sec.count))")
            let by = rail.frame.minY + y
            let half = bubble.bounds.height / 2
            bubble.center = CGPoint(x: rail.frame.minX - ZTokens.Space.n4 - bubble.bounds.width / 2,
                                    y: min(max(by, half + ZTokens.Space.n3), bounds.height - half - ZTokens.Space.n3))
            if phase == .began { bubble.setVisible(true, reduceMotion: reduceMotion) }
        } else {
            bubble.setVisible(false, reduceMotion: reduceMotion)
            noteScrolled()
        }
    }

    /// VoiceOver：上下轻扫切换分区。
    func stepSection(_ delta: Int) {
        guard !rowMap.sections.isEmpty else { return }
        let first = scrollWindow.firstVisibleRow(physical: Double(collectionView.contentOffset.y))
        let s = rowMap.sectionIndex(forRow: first)
        let target = min(rowMap.sections.count - 1, max(0, s + delta))
        jump(toRow: rowMap.sections[target].headerRow)
    }

    func currentSectionDescription() -> String {
        guard !rowMap.sections.isEmpty else { return "" }
        let first = scrollWindow.firstVisibleRow(physical: Double(collectionView.contentOffset.y))
        let sec = rowMap.sections[rowMap.sectionIndex(forRow: first)]
        return ZL.s("%@，%@ 个", sec.name, ZFormat.count(sec.count))
    }
}

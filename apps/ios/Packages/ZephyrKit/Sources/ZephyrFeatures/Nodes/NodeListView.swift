// NodeListView — 1e8 行节点虚拟列表（UIKit）。
//
// 结构：UICollectionView（NodeListLayout 固定行高）+ 置顶地区头 + 右侧索引条/气泡 + 底部位置信息。
// 虚拟偏移方案见 VirtualScrollWindow：物理 contentSize 封顶 4096 行，滚动中靠近窗口边缘时平移 baseRow 并等量回拨
// contentOffset（整行对齐，像素不变，惯性不断）。数据按可见窗口经 NodeRowStore 分页拉取并 LRU 缓存。
// 滚动逻辑在 NodeListView+Scrolling.swift。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

@MainActor
final class NodeListView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    let layout = NodeListLayout()
    let collectionView: UICollectionView
    let pinned = NodePinnedHeaderView()
    let rail = NodeIndexRail()
    let bubble = NodeRailBubble()
    let footer = NodeListFooterView()

    let store: NodeRowStore
    var rowMap = NodeRowMap.empty
    var scrollWindow = VirtualScrollWindow(rowCount: 0, rowHeight: ZTokens.Layout.rowHeight)
    var style: NodeListStyle
    var accent: Color = ZTokens.Accent.blue.color
    var reduceMotion = false
    var onSelect: ((NodeSummary) -> Void)?

    // 滚动状态（见 +Scrolling）
    var isAdjusting = false
    var lastPhysicalY: CGFloat = 0
    var scrollDirection = 0
    var settleDeadline: CFTimeInterval = 0
    var settleScheduled = false
    var appliedGeneration = -1

    init(store: NodeRowStore) {
        self.store = store
        self.style = NodeListStyle.make(traits: UITraitCollection.current, accent: ZTokens.Accent.blue.color)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (self: NodeListView, _) in self.applyStyle() }
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false   // 物理指示条只反映窗口；位置看底部 “n / total” 与索引条
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.decelerationRate = .normal
        collectionView.isPrefetchingEnabled = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(NodeCell.self, forCellWithReuseIdentifier: NodeCell.reuseID)
        collectionView.register(NodeHeaderCell.self, forCellWithReuseIdentifier: NodeHeaderCell.reuseID)
        addSubview(collectionView)
        addSubview(pinned)
        addSubview(footer)
        addSubview(bubble)
        addSubview(rail)
        layout.bottomInset = NodeListStyle.footerHeight - ZTokens.Space.n5

        store.onPageLoaded = { [weak self] page in self?.pageLoaded(page) }
        store.onLatencyChanged = { [weak self] ids in self?.latencyChanged(ids) }
        rail.onTrack = { [weak self] f, phase, y in self?.railTracked(f, phase: phase, y: y) }
        rail.onStep = { [weak self] d in self?.stepSection(d) }
        rail.currentValue = { [weak self] in self?.currentSectionDescription() ?? "" }
        applyStyle()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // MARK: 外部输入

    /// 新结果集：重置到顶部。generation 相同则忽略（SwiftUI 重复 update）。
    func apply(rowMap: NodeRowMap, generation: Int) {
        guard generation != appliedGeneration else { return }
        appliedGeneration = generation
        self.rowMap = rowMap
        scrollWindow.reset(rowCount: rowMap.rowCount)
        collectionView.reloadData()
        isAdjusting = true
        collectionView.setContentOffset(.zero, animated: false)   // 同时打断进行中的惯性
        collectionView.layoutIfNeeded()
        isAdjusting = false
        lastPhysicalY = 0
        rail.setCodes(rowMap.sections.map(\.region), style: style)
        updateChrome()
        requestVisiblePages()
        noteScrolled()
    }

    func setAccent(_ c: Color, reduceMotion rm: Bool) {
        reduceMotion = rm
        guard c != accent else { return }
        accent = c
        applyStyle()
    }

    /// 跳到某逻辑行（菜单“跳到地区”、VoiceOver 调整）。
    func jump(toRow row: Int64) {
        let vp = Double(viewportHeight)
        // 节点行落在置顶头下方，而不是被它盖住。
        var isNodeRow = false
        if !rowMap.isEmpty, case .node = rowMap.row(at: row) { isNodeRow = true }
        let pinnedOffset = isNodeRow ? Double(NodeListStyle.pinnedHeight) : 0
        isAdjusting = true
        if let fast = scrollWindow.physicalOffsetInWindow(row: row, viewport: vp) {
            // 快路径：目标在当前窗口内，只改偏移（索引条拖动的常态）。
            collectionView.setContentOffset(CGPoint(x: 0, y: max(0, fast - pinnedOffset)), animated: false)
        } else {
            let y = scrollWindow.jump(toRow: row, viewport: vp)
            collectionView.reloadData()
            collectionView.setContentOffset(CGPoint(x: 0, y: max(0, y - pinnedOffset)), animated: false)
        }
        collectionView.layoutIfNeeded()
        isAdjusting = false
        lastPhysicalY = collectionView.contentOffset.y
        scrollDirection = 0
        updateChrome()
        requestVisiblePages()
        noteScrolled()
    }

    // MARK: 样式

    func applyStyle() {
        let newStyle = NodeListStyle.make(traits: traitCollection, accent: accent)
        let heightChanged = newStyle.rowHeight != style.rowHeight
        style = newStyle
        pinned.apply(style: style)
        bubble.apply(style: style)
        footer.apply(style: style)
        footer.set(tested: store.testedCount)
        rail.setCodes(rowMap.sections.map(\.region), style: style)
        if heightChanged {
            let keep = scrollWindow.firstVisibleRow(physical: Double(collectionView.contentOffset.y))
            let y = scrollWindow.setRowHeight(Double(style.rowHeight), keepingRow: keep, viewport: Double(viewportHeight))
            layout.rowHeight = style.rowHeight
            isAdjusting = true
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            isAdjusting = false
        } else {
            layout.rowHeight = style.rowHeight
            reconfigureVisible()
        }
        updateChrome()
    }

    }

    // MARK: 布局

    var viewportHeight: CGFloat { max(style.rowHeight, collectionView.bounds.height - layout.bottomInset) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        if collectionView.frame != b { collectionView.frame = b }
        // 置顶头用 bounds + center 定位，“被推走”只改 transform（见 updateChrome）。
        pinned.bounds = CGRect(x: 0, y: 0, width: b.width, height: NodeListStyle.pinnedHeight)
        pinned.center = CGPoint(x: b.width / 2, y: NodeListStyle.pinnedHeight / 2)
        footer.frame = CGRect(x: 0, y: b.height - NodeListStyle.footerHeight, width: b.width, height: NodeListStyle.footerHeight)
        let railW = NodeListStyle.railTouchWidth
        let railTop = NodeListStyle.pinnedHeight + ZTokens.Space.n2
        rail.frame = CGRect(x: b.width - railW - ZTokens.Space.n1, y: railTop,
                            width: railW, height: max(0, b.height - railTop - NodeListStyle.footerHeight))
        updateChrome()
    }

    // MARK: 数据源

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        scrollWindow.physicalRowCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let row = scrollWindow.logicalRow(forItem: indexPath.item)
        switch rowMap.row(at: row) {
        case .header(let s):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NodeHeaderCell.reuseID, for: indexPath) as! NodeHeaderCell
            let sec = rowMap.sections[s]
            cell.configure(code: sec.region, name: sec.name, count: ZFormat.count(sec.count), style: style)
            return cell
        case .node(_, let ordinal, _):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NodeCell.reuseID, for: indexPath) as! NodeCell
            configure(cell, ordinal: ordinal)
            return cell
        }
    }

    func configure(_ cell: NodeCell, ordinal: Int64) {
        let node = store.node(atOrdinal: ordinal)
        cell.configure(node: node, latency: node.flatMap { store.latencyState(for: $0) }, highlights: store.highlights, style: style)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard case .node(_, let ordinal, _) = rowMap.row(at: scrollWindow.logicalRow(forItem: indexPath.item)),
              let node = store.node(atOrdinal: ordinal) else { return }
        onSelect?(node)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .node = rowMap.row(at: scrollWindow.logicalRow(forItem: indexPath.item)) { return true }
        return false
    }

    // MARK: 局部刷新

    /// 遍历可见 cell（≤ 20 个）直接重配，不走 reload。
    func reconfigureVisible(where match: ((Int64) -> Bool)? = nil) {
        for ip in collectionView.indexPathsForVisibleItems {
            let row = scrollWindow.logicalRow(forItem: ip.item)
            switch rowMap.row(at: row) {
            case .node(_, let ordinal, _):
                guard match?(ordinal) ?? true, let cell = collectionView.cellForItem(at: ip) as? NodeCell else { continue }
                configure(cell, ordinal: ordinal)
            case .header(let s):
                guard match == nil, let cell = collectionView.cellForItem(at: ip) as? NodeHeaderCell else { continue }
                let sec = rowMap.sections[s]
                cell.configure(code: sec.region, name: sec.name, count: ZFormat.count(sec.count), style: style)
            }
        }
    }

    private func pageLoaded(_ page: Int64) {
        let lo = page * NodeRowStore.pageSize, hi = lo + NodeRowStore.pageSize
        reconfigureVisible { $0 >= lo && $0 < hi }
        noteScrolled()   // 可见数据到达后重新计时 400ms，再测速
    }

    private func latencyChanged(_ ids: Set<NodeId>) {
        for ip in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: ip) as? NodeCell, let id = cell.nodeId, ids.contains(id),
                  case .node(_, let ordinal, _) = rowMap.row(at: scrollWindow.logicalRow(forItem: ip.item)),
                  let node = store.node(atOrdinal: ordinal) else { continue }
            cell.setLatency(store.latencyState(for: node), style: style)
        }
        footer.set(tested: store.testedCount)
    }
}

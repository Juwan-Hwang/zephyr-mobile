// NodeListLayout — 固定行高的 UICollectionViewLayout。
//
// 不缓存全部 attributes（物理窗口最多 4096 项，但可见只有 ~20 项）：按 rect 直接算出行区间，
// 复用一个小字典里的 attributes 对象，滚动时几乎零分配；没有 self-sizing、没有 AutoLayout 测量。

import UIKit

final class NodeListLayout: UICollectionViewLayout {
    var rowHeight: CGFloat = 52 {
        didSet { if rowHeight != oldValue { invalidateLayout() } }
    }
    /// 底部额外留白（让最后一行能滚到底部信息区之上）。
    var bottomInset: CGFloat = 0 {
        didSet { if bottomInset != oldValue { invalidateLayout() } }
    }

    private var itemCount = 0
    private var width: CGFloat = 0
    private var pool: [Int: UICollectionViewLayoutAttributes] = [:]

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        let n = cv.numberOfSections > 0 ? cv.numberOfItems(inSection: 0) : 0
        if n != itemCount || cv.bounds.width != width {
            pool.removeAll(keepingCapacity: true)
        }
        itemCount = n
        width = cv.bounds.width
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: width, height: CGFloat(itemCount) * rowHeight + bottomInset)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard itemCount > 0, rowHeight > 0 else { return [] }
        let first = max(0, Int(floor(rect.minY / rowHeight)))
        let last = min(itemCount - 1, Int(ceil(rect.maxY / rowHeight)))
        guard first <= last else { return [] }
        var out: [UICollectionViewLayoutAttributes] = []
        out.reserveCapacity(last - first + 1)
        for i in first...last { out.append(attributes(for: i)) }
        // 控制池大小：只保留当前 rect 附近的对象。
        if pool.count > 256 {
            pool = pool.filter { abs($0.key - first) < 128 }
        }
        return out
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < itemCount else { return nil }
        return attributes(for: indexPath.item)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != width
    }

    private func attributes(for i: Int) -> UICollectionViewLayoutAttributes {
        let frame = CGRect(x: 0, y: CGFloat(i) * rowHeight, width: width, height: rowHeight)
        if let a = pool[i] {
            if a.frame != frame { a.frame = frame }
            return a
        }
        let a = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: i, section: 0))
        a.frame = frame
        pool[i] = a
        return a
    }

    override func invalidateLayout() {
        super.invalidateLayout()
        pool.removeAll(keepingCapacity: true)
    }
}

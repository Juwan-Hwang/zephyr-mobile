// NodeListFooterView — 底部“1 / 13,109,802”与“已检测 41,288”（原型 .vfoot：70pt，向背景渐隐）。

import UIKit
import ZephyrKit

final class NodeListFooterView: UIView {
    private let gradient = CAGradientLayer()
    private let positionLabel = UILabel()
    private let testedLabel = UILabel()
    private var lastOrdinal: Int64 = -1
    private var lastTotal: Int64 = -1
    private var lastTested: Int64 = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        gradient.locations = [0, 0.4]
        testedLabel.textAlignment = .right
        addSubview(positionLabel)
        addSubview(testedLabel)
        positionLabel.isAccessibilityElement = false
        testedLabel.isAccessibilityElement = false
        isAccessibilityElement = true
        accessibilityTraits = [.staticText, .updatesFrequently]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(style: NodeListStyle) {
        gradient.colors = [style.background.withAlphaComponent(0).cgColor, style.background.cgColor]
        for l in [positionLabel, testedLabel] {
            l.font = style.footerFont
            l.textColor = style.textTertiary
        }
        lastOrdinal = -1; lastTested = -1
        setNeedsLayout()
    }

    /// 每帧可调用：数值不变时不做任何事。
    func set(ordinal: Int64, total: Int64) {
        guard ordinal != lastOrdinal || total != lastTotal else { return }
        lastOrdinal = ordinal; lastTotal = total
        positionLabel.text = total > 0 ? "\(CompactCount.grouped(ordinal)) / \(CompactCount.grouped(total))" : nil
        updateAccessibility()
    }

    private func updateAccessibility() {
        var parts: [String] = []
        if lastTotal > 0 { parts.append(ZL.s("第 %1$@ 个，共 %2$@ 个", CompactCount.grouped(lastOrdinal), CompactCount.grouped(lastTotal))) }
        if lastTested >= 0 { parts.append(ZL.s("已检测 %@ 个", CompactCount.grouped(lastTested))) }
        accessibilityLabel = parts.joined(separator: ZL.tr("，"))
    }

    func set(tested: Int64) {
        guard tested != lastTested else { return }
        lastTested = tested
        testedLabel.text = ZL.s("已检测 %@", CompactCount.grouped(tested))
        updateAccessibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let lead = NodeListStyle.leading
        let h = ceil(positionLabel.font?.lineHeight ?? 14)
        let top: CGFloat = 12
        let half = (bounds.width - lead * 2) / 2
        positionLabel.frame = CGRect(x: lead, y: top, width: half, height: h)
        testedLabel.frame = CGRect(x: lead + half, y: top, width: half, height: h)
    }
}

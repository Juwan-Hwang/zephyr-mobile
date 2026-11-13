// NodeCell — 节点行。手动布局（无 AutoLayout），固定行高，复用时只改文本与颜色。
//
//   [名称（高亮）×1.5]                 [协议]  [152 ms]  ← 右侧留出索引条
// 大字体（isXL）时隐藏协议列，与原型 .device.xl 一致。

import UIKit
import ZephyrKit

final class NodeCell: UICollectionViewCell {
    static let reuseID = "NodeCell"

    private let nameLabel = UILabel()
    let protocolLabel = UILabel()
    private let latencyLabel = UILabel()
    private let skeleton = CALayer()
    private let separator = CALayer()
    private var style: NodeListStyle?
    private(set) var nodeId: NodeId?
    private var accessibilityParts: (name: String, proto: String, latency: String, mult: String?) = ("", "", "", nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: NodeCell, _) in self.setNeedsLayout() }
        contentView.layer.addSublayer(separator)
        contentView.layer.addSublayer(skeleton)
        skeleton.cornerRadius = 4
        nameLabel.lineBreakMode = .byTruncatingTail
        protocolLabel.textAlignment = .right
        latencyLabel.textAlignment = .right
        for l in [nameLabel, protocolLabel, latencyLabel] {
            l.isOpaque = false
            l.adjustsFontForContentSizeCategory = false   // 字体由 NodeListStyle 统一下发
            contentView.addSubview(l)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? style?.skeleton : nil }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nodeId = nil
    }

    /// node 为 nil：数据页尚未到达，显示骨架条。
    func configure(node: NodeSummary?, latency: NodeRowStore.LatencyState?, highlights: [String], style: NodeListStyle) {
        if self.style?.rowHeight != style.rowHeight || self.style?.isXL != style.isXL { setNeedsLayout() }
        self.style = style
        separator.backgroundColor = style.separator.cgColor
        skeleton.backgroundColor = style.skeleton.cgColor
        protocolLabel.isHidden = style.isXL || node == nil
        guard let node else {
            nodeId = nil
            nameLabel.attributedText = nil
            latencyLabel.text = nil
            skeleton.isHidden = false
            accessibilityLabel = ZL.tr("正在载入")
            return
        }
        skeleton.isHidden = true
        nodeId = node.id
        let markup = NodeNameMarkup(name: node.name, highlights: highlights)
        nameLabel.attributedText = Self.attributed(markup, style: style)
        protocolLabel.font = style.protocolFont
        protocolLabel.textColor = style.textTertiary
        protocolLabel.text = node.protocol
        accessibilityParts = (markup.base, node.protocol, "", markup.multiplier)
        setLatency(latency, style: style)
    }

    /// 只刷新延迟列（latencyUpdates 局部刷新）。
    func setLatency(_ state: NodeRowStore.LatencyState?, style: NodeListStyle) {
        let (text, color) = style.latencyAppearance(state)
        latencyLabel.font = style.latencyFont
        latencyLabel.textColor = color
        latencyLabel.text = text
        let spoken: String
        switch state {
        case .none: spoken = ZL.tr("未测速")
        case .testing: spoken = ZL.tr("正在测速")
        case .value(let ms) where ms < 0: spoken = ZL.tr("超时")
        case .value(let ms): spoken = ZL.f("%lld 毫秒", Int64(ms))
        }
        accessibilityParts.latency = spoken
        var parts = [accessibilityParts.name]
        if let m = accessibilityParts.mult { parts.append(ZL.s("倍率 %@", String(m.dropFirst()))) }
        parts += [accessibilityParts.proto, spoken]
        accessibilityLabel = parts.joined(separator: ZL.tr("，"))
    }

    private static func attributed(_ m: NodeNameMarkup, style: NodeListStyle) -> NSAttributedString {
        let s = NSMutableAttributedString(string: m.base, attributes: [.font: style.nameFont, .foregroundColor: style.textPrimary])
        for r in m.highlights {
            s.addAttribute(.foregroundColor, value: style.accent, range: NSRange(location: r.lowerBound, length: r.count))
        }
        if let mult = m.multiplier {
            s.append(NSAttributedString(string: " " + mult, attributes: [.font: style.multiplierFont, .foregroundColor: style.textTertiary]))
        }
        return s
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let style else { return }
        let b = contentView.bounds
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        let hair = 1 / scale
        let lead = NodeListStyle.leading, trail = NodeListStyle.trailing
        CATransaction.begin(); CATransaction.setDisableActions(true)
        separator.frame = CGRect(x: lead, y: b.height - hair, width: b.width - lead, height: hair)
        skeleton.frame = CGRect(x: lead, y: (b.height - 10) / 2, width: min(180, b.width * 0.45), height: 10)
        CATransaction.commit()

        let gap: CGFloat = 12
        let latW = style.latencyWidth
        var right = b.width - trail
        latencyLabel.frame = CGRect(x: right - latW, y: 0, width: latW, height: b.height).integral
        right -= latW + gap
        if !protocolLabel.isHidden {
            let pw = ceil(protocolLabel.sizeThatFits(CGSize(width: 80, height: b.height)).width)
            protocolLabel.frame = CGRect(x: right - pw, y: 0, width: pw, height: b.height).integral
            right -= pw + gap
        }
        nameLabel.frame = CGRect(x: lead + 2, y: 0, width: max(0, right - lead - 2), height: b.height).integral
    }
}

// NodeHeaderCell — 地区分区头（列表内行）与置顶头（NodePinnedHeaderView）共用的内容视图。
//
//   [US] 美国                                3,118,402

import UIKit

/// 分区头内容：地区码方框徽标 + 名称 + 计数。手动布局。
final class NodeRegionHeaderContent: UIView {
    private let codeLabel = UILabel()
    private let codeBox = CALayer()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    /// 内容顶部留白（列表内头行原型有 padding-top:14，内容偏下；置顶头为 0）。
    var contentTopInset: CGFloat = 0 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(codeBox)
        codeBox.cornerRadius = 4
        codeBox.borderWidth = 1
        codeLabel.textAlignment = .center
        countLabel.textAlignment = .right
        [codeLabel, nameLabel, countLabel].forEach(addSubview)
        isAccessibilityElement = true
        accessibilityTraits = .header
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(code: String, name: String, count: String, style: NodeListStyle) {
        codeLabel.font = style.headerCodeFont
        codeLabel.textColor = style.textSecondary
        codeLabel.text = code
        codeBox.borderColor = style.badgeBorder.cgColor
        nameLabel.font = style.headerNameFont
        nameLabel.textColor = style.textPrimary
        nameLabel.text = name
        countLabel.font = style.headerCountFont
        countLabel.textColor = style.textTertiary
        countLabel.text = count
        accessibilityLabel = "\(name)，\(count) 个节点"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let lead = NodeListStyle.leading, trail = NodeListStyle.trailing
        let midY = contentTopInset + (b.height - contentTopInset) / 2
        let codeSize = codeLabel.sizeThatFits(.zero)
        let boxW = ceil(codeSize.width) + 12, boxH = ceil(codeSize.height) + 6
        let box = CGRect(x: lead, y: midY - boxH / 2, width: boxW, height: boxH).integral
        CATransaction.begin(); CATransaction.setDisableActions(true)
        codeBox.frame = box
        CATransaction.commit()
        codeLabel.frame = box
        let cw = ceil(countLabel.sizeThatFits(.zero).width)
        countLabel.frame = CGRect(x: b.width - trail - cw, y: 0, width: cw, height: b.height).offsetBy(dx: 0, dy: midY - b.height / 2).integral
        let nx = box.maxX + 8
        nameLabel.frame = CGRect(x: nx, y: 0, width: max(0, countLabel.frame.minX - 8 - nx), height: b.height).offsetBy(dx: 0, dy: midY - b.height / 2).integral
    }
}

final class NodeHeaderCell: UICollectionViewCell {
    static let reuseID = "NodeHeaderCell"
    private let content = NodeRegionHeaderContent()
    private let separator = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(content)
        contentView.layer.addSublayer(separator)
        content.contentTopInset = 14   // 原型 .vr.hd{padding-top:14px}
        isAccessibilityElement = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(code: String, name: String, count: String, style: NodeListStyle) {
        content.configure(code: code, name: name, count: count, style: style)
        separator.backgroundColor = style.separator.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = contentView.bounds
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        separator.frame = CGRect(x: NodeListStyle.leading, y: contentView.bounds.height - 1 / scale,
                                 width: contentView.bounds.width - NodeListStyle.leading, height: 1 / scale)
        CATransaction.commit()
    }
}

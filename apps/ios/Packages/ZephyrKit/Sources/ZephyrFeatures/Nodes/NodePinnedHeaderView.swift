// NodePinnedHeaderView — 置顶地区头（原型 .vpin：40pt、86% 背景 + 模糊、底部细线）。
// 下一个分区头顶上来时被向上推走（与系统 plain 列表的置顶头行为一致）。

import UIKit

final class NodePinnedHeaderView: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let tint = UIView()
    private let content = NodeRegionHeaderContent()
    private let hairline = CALayer()
    private var currentKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(blur)
        addSubview(tint)
        addSubview(content)
        layer.addSublayer(hairline)
        isHidden = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(style: NodeListStyle) {
        tint.backgroundColor = style.background.withAlphaComponent(0.86)
        hairline.backgroundColor = style.separator.cgColor
        currentKey = ""
    }

    /// key 用于避免每帧重复设置文本。
    func show(code: String, name: String, count: String, style: NodeListStyle) {
        let key = code + "|" + count
        guard key != currentKey else { return }
        currentKey = key
        content.configure(code: code, name: name, count: count, style: style)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        tint.frame = bounds
        content.frame = bounds
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hairline.frame = CGRect(x: 0, y: bounds.height - 1 / scale, width: bounds.width, height: 1 / scale)
        CATransaction.commit()
    }
}

// NodeIndexRail — 右侧地区索引条（原型 .vrail）+ 拖动气泡（原型 .bub）。
//
// 直接重写 touches（比手势识别器少一帧延迟，也不会与列表的 pan 抢手势）。
// 竖向比例 f → 由 NodeListView 换算成目标行（先等分到分区，再按分区内比例）并跳转。
// 跨分区时 UISelectionFeedbackGenerator 触感一次。VoiceOver 下是“可调整”元素：上下轻扫切换分区。

import UIKit
import ZephyrDesign
import ZephyrKit

final class NodeIndexRail: UIView {
    enum Phase { case began, changed, ended }

    /// (比例 0..<1, 阶段, 触点在 rail 内的 y)
    var onTrack: ((Double, Phase, CGFloat) -> Void)?
    /// VoiceOver 调整：+1 下一分区，-1 上一分区。
    var onStep: ((Int) -> Void)?
    /// VoiceOver 读出的当前值。
    var currentValue: (() -> String)?

    private var labels: [UILabel] = []
    private var codes: [String] = []
    private var style: NodeListStyle?
    private let feedback = UISelectionFeedbackGenerator()
    private var lastSection = -1
    private let topInset: CGFloat = 6, bottomInset: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        isAccessibilityElement = true
        accessibilityLabel = ZL.tr("地区索引")
        accessibilityTraits = .adjustable
        accessibilityHint = ZL.tr("上下轻扫切换地区")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setCodes(_ codes: [String], style: NodeListStyle) {
        self.style = style
        if codes != self.codes || labels.count != codes.count {
            self.codes = codes
            labels.forEach { $0.removeFromSuperview() }
            labels = codes.map { code in
                let l = UILabel()
                l.text = code
                l.textAlignment = .center
                l.isAccessibilityElement = false
                addSubview(l)
                return l
            }
        }
        for l in labels { l.font = style.railFont; l.textColor = style.accent }
        isHidden = codes.count < 2
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !labels.isEmpty else { return }
        let h = bounds.height - topInset - bottomInset
        let lh = ceil(style?.railFont.lineHeight ?? 12)
        let step = labels.count > 1 ? (h - lh) / CGFloat(labels.count - 1) : 0
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 0, y: topInset + CGFloat(i) * step, width: bounds.width, height: lh).integral
        }
    }

    // MARK: 触摸

    private func fraction(_ t: UITouch) -> (Double, CGFloat) {
        let y = t.location(in: self).y
        let h = max(1, bounds.height - topInset - bottomInset)
        return (Double(min(max(0, (y - topInset) / h), 0.999_999)), y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        feedback.prepare()
        lastSection = -1
        let (f, y) = fraction(t)
        tick(f)
        onTrack?(f, .began, y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let (f, y) = fraction(t)
        tick(f)
        onTrack?(f, .changed, y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let (f, y) = touches.first.map { fraction($0) } ?? (0, 0)
        onTrack?(f, .ended, y)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    /// 跨分区触感（“按段跳转”）。
    private func tick(_ f: Double) {
        guard !codes.isEmpty else { return }
        let s = min(codes.count - 1, Int(f * Double(codes.count)))
        if s != lastSection {
            if lastSection >= 0 { feedback.selectionChanged(); feedback.prepare() }
            lastSection = s
        }
    }

    // MARK: 无障碍

    override func accessibilityIncrement() { onStep?(1) }
    override func accessibilityDecrement() { onStep?(-1) }
    override var accessibilityValue: String? {
        get { currentValue?() }
        set {}
    }
}

/// 拖动索引条时的气泡：“US 美国” / “1,234 / 3,118,402”。
final class NodeRailBubble: UIView {
    private let title = UILabel()
    private let subtitle = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = ZTokens.Radius.md + 4   // 原型 .bub border-radius:20px
        layer.cornerCurve = .continuous
        addSubview(title)
        addSubview(subtitle)
        alpha = 0
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(style: NodeListStyle) {
        backgroundColor = style.bubbleBackground
        title.font = style.bubbleTitleFont
        title.textColor = style.textPrimary
        subtitle.font = style.bubbleSubFont
        subtitle.textColor = style.textTertiary
    }

    func set(title t: String, subtitle s: String) {
        if title.text != t { title.text = t }
        subtitle.text = s
        let w = max(92, ceil(max(title.sizeThatFits(.zero).width, subtitle.sizeThatFits(.zero).width)) + 32)
        if abs(bounds.width - w) > 0.5 { bounds.size = CGSize(width: w, height: 64) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let th = ceil(title.font.lineHeight), sh = ceil(subtitle.font.lineHeight)
        let top = (bounds.height - th - sh - 2) / 2
        title.frame = CGRect(x: 16, y: top, width: bounds.width - 32, height: th)
        subtitle.frame = CGRect(x: 16, y: top + th + 2, width: bounds.width - 32, height: sh)
    }

    func setVisible(_ visible: Bool, reduceMotion: Bool) {
        let target: CGAffineTransform = visible || reduceMotion ? .identity : CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: ZTokens.Time.standard, delay: visible ? 0 : ZTokens.Time.standard * 2.5, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = visible ? 1 : 0
            self.transform = target
        }
    }
}

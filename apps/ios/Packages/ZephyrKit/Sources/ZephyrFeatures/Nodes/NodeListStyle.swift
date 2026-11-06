// NodeListStyle — 节点列表 UIKit 层的度量、字体与已解析颜色。
//
// 只在 trait（深浅色 / Dynamic Type）或强调色变化时重建一次，然后整体下发给 cell；
// 滚动热路径上不做任何动态色解析或字体查找。

import SwiftUI
import UIKit
import ZephyrDesign

@MainActor
struct NodeListStyle {
    /// 原型 `.device.xl .vr{height:66px}`。tokens 只有 Layout.rowHeight(52)；已在 NOTES-L 请 A 增补 rowHeightXl。
    static let rowHeightXL: CGFloat = 66
    /// 固定行高下名称字号的上限（52pt 行最多容纳 17pt；66pt 行 19pt，与原型大字体一致）。
    static let nameCap: CGFloat = 17
    static let nameCapXL: CGFloat = 19
    /// 置顶头高度（原型 .vpin 40px）
    static let pinnedHeight: CGFloat = ZTokens.Space.n7 + ZTokens.Space.n3
    /// 底部信息区高度（原型 .vfoot 70px，含渐隐）
    static let footerHeight: CGFloat = ZTokens.Space.n8 + ZTokens.Space.n6 - ZTokens.Space.n1 / 2
    /// 右侧索引条宽度（原型 30px 触控区）；tokens Layout.indexRailWidth 是字形列宽。
    static let railTouchWidth: CGFloat = ZTokens.Layout.indexRailWidth + ZTokens.Space.n4 - 2
    /// 行左右内边距（原型 padding: 0 44px 0 22px）
    static let leading: CGFloat = ZTokens.Space.n6 - 2
    static let trailing: CGFloat = ZTokens.Layout.touchMinIos

    var isXL: Bool
    var rowHeight: CGFloat

    var nameFont: UIFont
    var multiplierFont: UIFont
    var protocolFont: UIFont
    var latencyFont: UIFont
    var latencyWidth: CGFloat
    var headerCodeFont: UIFont
    var headerNameFont: UIFont
    var headerCountFont: UIFont
    var footerFont: UIFont
    var bubbleTitleFont: UIFont
    var bubbleSubFont: UIFont
    var railFont: UIFont

    var textPrimary: UIColor
    var textSecondary: UIColor
    var textTertiary: UIColor
    var textQuaternary: UIColor
    var separator: UIColor
    var badgeBorder: UIColor
    var accent: UIColor
    var warning: UIColor
    var danger: UIColor
    var background: UIColor
    var bubbleBackground: UIColor
    var skeleton: UIColor

    static func make(traits: UITraitCollection, accent: Color) -> NodeListStyle {
        let category = traits.preferredContentSizeCategory
        let xl = category >= .extraExtraLarge
        let body = UIFontMetrics(forTextStyle: .body)
        let foot = UIFontMetrics(forTextStyle: .footnote)
        let cap1 = UIFontMetrics(forTextStyle: .caption1)
        func mono(_ size: CGFloat, _ w: UIFont.Weight = .regular) -> UIFont { .monospacedSystemFont(ofSize: size, weight: w) }
        func r(_ c: Color) -> UIColor { UIColor(c).resolvedColor(with: traits) }

        let nameBase = ZTokens.TypeStyle.button.size          // 15
        let latBase = ZTokens.TypeStyle.footnote.size         // 13
        let name = body.scaledFont(for: .systemFont(ofSize: nameBase), maximumPointSize: xl ? nameCapXL : nameCap, compatibleWith: traits)
        let lat = foot.scaledFont(for: mono(latBase), maximumPointSize: xl ? 16 : 14, compatibleWith: traits)
        let primary = r(ZTokens.Colors.textPrimary)
        let tertiary = r(ZTokens.Colors.textTertiary)

        return NodeListStyle(
            isXL: xl,
            rowHeight: xl ? rowHeightXL : ZTokens.Layout.rowHeight,
            nameFont: name,
            multiplierFont: cap1.scaledFont(for: mono(ZTokens.TypeStyle.caption.size), maximumPointSize: 14, compatibleWith: traits),
            protocolFont: mono(ZTokens.FontSize.n2xs + 0.5),
            latencyFont: lat,
            latencyWidth: xl ? rowHeightXL : ZTokens.Layout.rowHeight,
            headerCodeFont: mono(ZTokens.FontSize.n2xs + 1, .semibold),
            headerNameFont: foot.scaledFont(for: .systemFont(ofSize: latBase, weight: .medium), maximumPointSize: xl ? 17 : 15, compatibleWith: traits),
            headerCountFont: cap1.scaledFont(for: mono(ZTokens.TypeStyle.caption.size), maximumPointSize: 15, compatibleWith: traits),
            footerFont: cap1.scaledFont(for: mono(ZTokens.TypeStyle.caption.size - 0.5), maximumPointSize: 15, compatibleWith: traits),
            bubbleTitleFont: .systemFont(ofSize: ZTokens.TypeStyle.title.size, weight: .medium),
            bubbleSubFont: mono(ZTokens.FontSize.xs - 1),
            railFont: mono(ZTokens.FontSize.n2xs - 0.5, .semibold),
            textPrimary: primary,
            textSecondary: r(ZTokens.Colors.textSecondary),
            textTertiary: tertiary,
            textQuaternary: tertiary.withAlphaComponent(tertiary.cgColor.alpha * 0.5),
            separator: r(ZTokens.Colors.borderSubtle),
            badgeBorder: r(ZTokens.Colors.borderDefault),
            accent: r(accent),
            warning: r(ZTokens.Colors.latencyFair),
            danger: r(ZTokens.Colors.latencyBad),
            background: .systemGroupedBackground.resolvedColor(with: traits),
            bubbleBackground: r(ZTokens.Colors.bgElevated),
            skeleton: r(ZTokens.Colors.bgMuted)
        )
    }

    /// 原型：> 200ms 琥珀色，未测 “—” 最淡，测试中 “···”。超时显示“超时”（危险色）。
    func latencyAppearance(_ state: NodeRowStore.LatencyState?) -> (String, UIColor) {
        switch state {
        case .none: return ("—", textQuaternary)
        case .testing: return ("···", textQuaternary)
        case .value(let ms) where ms < 0: return ("超时", danger)
        case .value(let ms): return ("\(ms) ms", ms > ZTokens.LatencyThreshold.fair ? warning : textSecondary)
        }
    }
}

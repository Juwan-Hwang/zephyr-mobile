// H 页面里 ZTokens.TypeStyle 没有的原型字号（14 / 15 / 10.5 / 32…）。都随 Dynamic Type 缩放（@ScaledMetric），
// 数值集中在 HMetrics。TypeStyle 的成员初始化器是 internal，Features 里造不出新档位，所以单独一个修饰符。

import SwiftUI

struct HFontModifier: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigits: Bool
    let maxScale: CGFloat?
    let base: CGFloat
    /// em 为单位的字距（-0.03 = -0.03em）
    let trackingEm: CGFloat
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight, design: Font.Design,
         monospacedDigits: Bool, maxScale: CGFloat?, trackingEm: CGFloat) {
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
        self.maxScale = maxScale
        self.base = size
        self.trackingEm = trackingEm
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        let s = maxScale.map { min(size, base * $0) } ?? size
        let f = Font.system(size: s, weight: weight, design: design)
        content
            .font(monospacedDigits ? f.monospacedDigit() : f)
            .tracking(s * trackingEm)
    }
}

extension View {
    /// 原型里非 token 档位的字号，随 Dynamic Type 缩放。
    func hFont(_ size: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight = .regular,
               design: Font.Design = .default, monospacedDigits: Bool = false,
               maxScale: CGFloat? = nil, trackingEm: CGFloat = 0) -> some View {
        modifier(HFontModifier(size: size, relativeTo: relativeTo, weight: weight, design: design,
                               monospacedDigits: monospacedDigits, maxScale: maxScale, trackingEm: trackingEm))
    }
}

// 等宽字与大数字字型。ZTokens.TypeStyle 只有比例字体，原型里大量使用 SF Mono（延迟、地区码、规则），
// 以及 44–76pt 的超细大数字。这两个修饰符都随 Dynamic Type 缩放（大数字有上限）。

import SwiftUI

/// 等宽字号档位（来自原型 CSS，见 ZMetrics）。
public enum ZMonoSize: Sendable {
    case tag, micro, flag, small, body, large

    var points: CGFloat {
        switch self {
        case .tag: return ZMetrics.monoTag
        case .micro: return ZMetrics.monoMicro
        case .flag: return ZMetrics.monoFlag
        case .small: return ZMetrics.monoSmall
        case .body: return ZMetrics.monoBody
        case .large: return ZMetrics.monoLarge
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .tag, .micro, .flag: return .caption2
        case .small: return .caption
        case .body: return .footnote
        case .large: return .subheadline
        }
    }
}

struct ZMonoModifier: ViewModifier {
    let weight: Font.Weight
    @ScaledMetric private var size: CGFloat

    init(_ mono: ZMonoSize, weight: Font.Weight) {
        self.weight = weight
        _size = ScaledMetric(wrappedValue: mono.points, relativeTo: mono.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

/// 大数字档位。
public enum ZDisplaySize: Sendable {
    /// 76pt：场景 sheet 的可用数
    case hero
    /// 56pt：首页速率
    case large
    /// 44pt：页头计数 / 首页状态字
    case title
    /// 40pt：ZTokens.TypeStyle.metric
    case metric
    /// 30pt：资料库统计
    case small
    /// 22pt：ZTokens.TypeStyle.metricSm（diff 数字）
    case compact

    var points: CGFloat {
        switch self {
        case .hero: return ZMetrics.displayHero
        case .large: return ZMetrics.displayLarge
        case .title: return ZMetrics.displayTitle
        case .metric: return ZTokens.TypeStyle.metric.size
        case .small: return ZMetrics.displaySmall
        case .compact: return ZTokens.TypeStyle.metricSm.size
        }
    }

    var weight: Font.Weight {
        switch self {
        case .compact: return ZTokens.TypeStyle.metricSm.weight
        default: return ZTokens.TypeStyle.metric.weight
        }
    }
}

struct ZDisplayModifier: ViewModifier {
    let base: CGFloat
    let weight: Font.Weight
    @ScaledMetric private var scaled: CGFloat

    init(_ display: ZDisplaySize, weight: Font.Weight?) {
        base = display.points
        self.weight = weight ?? display.weight
        _scaled = ScaledMetric(wrappedValue: display.points, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        let size = min(scaled, base * ZMetrics.displayMaxScale)
        content
            .font(.system(size: size, weight: weight).monospacedDigit())
            .tracking(size * ZMetrics.displayTracking)
    }
}

public extension View {
    /// SF Mono，随 Dynamic Type 缩放。
    func zMono(_ size: ZMonoSize, weight: Font.Weight = .regular) -> some View {
        modifier(ZMonoModifier(size, weight: weight))
    }

    /// 超细大数字（等宽数字 + 负字距），随 Dynamic Type 缩放，最多放大 1.6 倍。
    func zDisplay(_ size: ZDisplaySize, weight: Font.Weight? = nil) -> some View {
        modifier(ZDisplayModifier(size, weight: weight))
    }
}

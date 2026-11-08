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
    /// 固定行高列表里用的字号上限（pt）；nil 不封顶。
    let maxSize: CGFloat?
    @ScaledMetric private var size: CGFloat

    init(_ mono: ZMonoSize, weight: Font.Weight, maxSize: CGFloat? = nil) {
        self.weight = weight
        self.maxSize = maxSize
        _size = ScaledMetric(wrappedValue: mono.points, relativeTo: mono.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: maxSize.map { min(size, $0) } ?? size, weight: weight, design: .monospaced))
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

    /// 字距（em）。原型各处大数字的 letter-spacing 不同，按档位取：
    /// `.big b` −0.05 · `.spd b` −0.045 · `.state` −0.035 · `.la .sp b` −0.04 · `.lc b` −0.03 · `.diff .rw b` −0.02。
    var trackingEm: CGFloat {
        switch self {
        case .hero: return ZMetrics.displayTrackingHero
        case .large: return ZMetrics.displayTrackingLarge
        case .title: return ZMetrics.displayTrackingTitle
        case .metric: return ZMetrics.displayTrackingMetric
        case .small: return ZMetrics.displayTrackingSmall
        case .compact: return ZMetrics.displayTrackingCompact
        }
    }
}

struct ZDisplayModifier: ViewModifier {
    let base: CGFloat
    let weight: Font.Weight
    let trackingEm: CGFloat
    @ScaledMetric private var scaled: CGFloat

    init(_ display: ZDisplaySize, weight: Font.Weight?, trackingEm: CGFloat? = nil) {
        base = display.points
        self.weight = weight ?? display.weight
        self.trackingEm = trackingEm ?? display.trackingEm
        _scaled = ScaledMetric(wrappedValue: display.points, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        let size = min(scaled, base * ZMetrics.displayMaxScale)
        content
            .font(.system(size: size, weight: weight).monospacedDigit())
            .tracking(size * trackingEm)
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

    /// 同上，但显式指定字距（em，如原型 `.pgh .ct b` 的 −0.04）。不传时按档位默认值。
    func zDisplay(_ size: ZDisplaySize, weight: Font.Weight? = nil, tracking em: CGFloat) -> some View {
        modifier(ZDisplayModifier(size, weight: weight, trackingEm: em))
    }
}

// MARK: - 原型字阶补充（ZTokens.TypeStyle 尚缺的档位，已在 NOTES-D 请 A 补 token；补齐后改为转发）

public extension ZTokens.TypeStyle {
    /// 14 / 500：`.btn` 按钮文字。
    static let zControl = ZTokens.TypeStyle(size: 14, weight: .medium, lineHeight: 18, relativeTo: .subheadline)
    /// 14 / 400：`.toast`、`.idle` 说明、`.li .val`。
    static let zCallout = ZTokens.TypeStyle(size: 14, weight: .regular, lineHeight: 20, relativeTo: .subheadline)
    /// 15 / 400：`.ex` 首页出口节点名、`.vr .nm` 节点名、`.li` 列表行。
    static let zRowValue = ZTokens.TypeStyle(size: 15, weight: .regular, lineHeight: 20, relativeTo: .subheadline)
    /// 13.5 / 400：`.seg button` 分段控件文字。
    static let zSegment = ZTokens.TypeStyle(size: 13.5, weight: .regular, lineHeight: 18, relativeTo: .footnote)
}

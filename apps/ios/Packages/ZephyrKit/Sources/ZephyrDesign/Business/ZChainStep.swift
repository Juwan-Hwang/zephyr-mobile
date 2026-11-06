// 步骤链的一步：左侧圆点 + 竖线，右侧 小标签 / 值 / 说明（+ 右侧等宽附注）。
// compact = 规则测试命中链（原型 `.chain .st`：9pt 空心点，标签 11.5 t3、值 14.5 或等宽 13、右侧 “#18,204,451”；末步实心强调色）
// regular = 连接轨迹（原型 `.step`：11pt 空心点，标签 12 t3、值 16、说明 12.5 t3；末步实心绿色）
// 用法：VStack(spacing: 0) 依次放各步，position 用 `.at(i, of: n)`；竖线在点与点之间连续。

import SwiftUI

public enum ZChainPosition: Sendable, Equatable {
    case first, middle, last, only

    /// 第 index 步（0 起）共 count 步时的位置。
    public static func at(_ index: Int, of count: Int) -> ZChainPosition {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        if index >= count - 1 { return .last }
        return .middle
    }

    var hasIncoming: Bool { self == .middle || self == .last }
    var hasOutgoing: Bool { self == .first || self == .middle }
    var isTerminal: Bool { self == .last || self == .only }
}

public enum ZChainStyle: Sendable {
    case compact, regular
}

public enum ZChainMarker: Sendable {
    case hollow, accent, success, warning, danger
}

public struct ZChainStep: View {
    private let label: String
    private let value: String
    private let detail: String?
    private let trailing: String?
    private let regionCode: String?
    private let monospacedValue: Bool
    private let position: ZChainPosition
    private let marker: ZChainMarker
    private let style: ZChainStyle
    @Environment(\.zAccent) private var accent

    /// - Parameters:
    ///   - label: 小标签，如 "第 4 层 · 广告与跟踪"、"规则"。
    ///   - value: 主值，如 "DOMAIN-KEYWORD,ads"、"新加坡 02"。
    ///   - detail: 值下方说明（regular 常用）。
    ///   - trailing: 右侧等宽附注，如 "#18,204,451"。
    ///   - regionCode: 值前的 ZFlag。
    ///   - marker: 圆点样式；默认末步 compact = 强调色、regular = 绿色，其余空心。
    public init(label: String,
                value: String,
                detail: String? = nil,
                trailing: String? = nil,
                regionCode: String? = nil,
                monospacedValue: Bool = false,
                position: ZChainPosition = .middle,
                marker: ZChainMarker? = nil,
                style: ZChainStyle = .compact) {
        self.label = label
        self.value = value
        self.detail = detail
        self.trailing = trailing
        self.regionCode = regionCode
        self.monospacedValue = monospacedValue
        self.position = position
        self.style = style
        self.marker = marker ?? (position.isTerminal ? (style == .compact ? .accent : .success) : .hollow)
    }

    public var body: some View {
        HStack(alignment: style == .compact ? .center : .top, spacing: style == .compact ? ZTokens.Space.n4 : ZTokens.Space.n5) {
            dot.padding(.top, style == .regular ? ZTokens.Space.n1 : 0)
            VStack(alignment: .leading, spacing: style == .compact ? 0 : ZTokens.Space.n1 / 2) {
                Text(verbatim: label)
                    .zType(.caption)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                HStack(spacing: ZTokens.Space.n3) {
                    if let regionCode { ZFlag(regionCode) }
                    valueText
                }
                if let detail {
                    Text(verbatim: detail)
                        .zType(.caption)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(verbatim: trailing)
                    .zMono(.small)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.top, style == .compact ? ZTokens.Space.n2 : 0)
        .padding(.bottom, style == .compact ? ZTokens.Space.n2 : ZTokens.Space.n6 - ZTokens.Space.n1 / 2)
        .background(alignment: .topLeading) { rail }
        .accessibilityElement(children: .combine)
    }

    private var dotSize: CGFloat { style == .compact ? ZMetrics.chainDot : ZMetrics.chainDotLarge }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(verbatim: value).foregroundStyle(ZTokens.Colors.textPrimary)
        if monospacedValue {
            text.zMono(.body).lineLimit(2)
        } else {
            text.zType(.body).lineLimit(style == .compact ? 1 : nil).truncationMode(.middle)
        }
    }

    private var dot: some View {
        Circle()
            .strokeBorder(markerColor ?? ZTokens.Colors.textTertiary, lineWidth: ZMetrics.chainDotStroke)
            .background(Circle().fill(markerColor ?? Color.clear))
            .frame(width: dotSize, height: dotSize)
            .accessibilityHidden(true)
    }

    private var markerColor: Color? {
        switch marker {
        case .hollow: return nil
        case .accent: return accent.color
        case .success: return ZSwitchColor.on
        case .warning: return ZTokens.Colors.colorWarning
        case .danger: return ZTokens.Colors.colorDanger
        }
    }

    /// 竖线：在本步内从顶部画到点上沿、从点下沿画到底部；相邻两步首尾相接。
    private var rail: some View {
        GeometryReader { geo in
            let topPad = style == .compact ? ZTokens.Space.n2 : 0
            let bottomPad = style == .compact ? ZTokens.Space.n2 : ZTokens.Space.n6 - ZTokens.Space.n1 / 2
            let contentH = geo.size.height - topPad - bottomPad
            let cy = style == .compact ? topPad + contentH / 2 : ZTokens.Space.n1 + dotSize / 2
            let x = dotSize / 2
            let gap = dotSize / 2 + ZMetrics.hairline * 2
            Path { p in
                if position.hasIncoming {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: max(cy - gap, 0)))
                }
                if position.hasOutgoing {
                    p.move(to: CGPoint(x: x, y: cy + gap))
                    p.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
            }
            .stroke(ZTokens.Colors.borderPrimary, lineWidth: ZMetrics.hairline)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
private struct ZChainSample: View {
    var body: some View {
        ZCard {
            VStack(spacing: 0) {
                ZChainStep(label: "请求", value: "chat.openai.com", monospacedValue: true, position: .first)
                ZChainStep(label: "第 3 层 · OpenAI", value: "DOMAIN-SUFFIX,openai.com", trailing: "#41", monospacedValue: true)
                ZChainStep(label: "场景 · AI", value: "新加坡 02", regionCode: "SG")
                ZChainStep(label: "出口 IP", value: "198.51.100.7", monospacedValue: true, position: .last)
            }
        }
        VStack(spacing: 0) {
            let steps = [("规则", "DOMAIN-SUFFIX,openai.com", "第 3 层 · OpenAI"),
                         ("场景", "AI", "9 个可用 · 自动选择"),
                         ("节点", "新加坡 02", "38 ms"),
                         ("出口", "198.51.100.7", "SG · Singapore")]
            ForEach(steps.indices, id: \.self) { i in
                ZChainStep(label: steps[i].0, value: steps[i].1, detail: steps[i].2,
                           position: .at(i, of: steps.count), style: .regular)
            }
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZChainSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZChainSample() } }
#Preview("强调色") { ZAccentMatrix { ZChainStep(label: "结果", value: "已拦截", position: .only) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZChainSample() } }

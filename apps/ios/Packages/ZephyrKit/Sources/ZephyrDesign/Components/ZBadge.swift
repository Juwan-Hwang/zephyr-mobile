// 小标签（原型 `.gr .tg`：等宽 10、1px 细边框、圆角 4；`.tg.b` 强调色边框 45%）。
// 规则层 “覆写 / 订阅 / 域名”、节点协议等。tone 决定文字与边框色；filled 变体用 14% 底色。

import SwiftUI

public enum ZBadgeTone: Sendable {
    case neutral, accent, success, warning, danger
}

public struct ZBadge: View {
    private let text: Text
    private let tone: ZBadgeTone
    private let filled: Bool
    @ScaledMetric(relativeTo: .caption2) private var hPad: CGFloat = ZTokens.Space.n1
    @ScaledMetric(relativeTo: .caption2) private var vPad: CGFloat = ZTokens.Space.n1 / 2

    public init(_ title: LocalizedStringKey, tone: ZBadgeTone = .neutral, filled: Bool = false) {
        self.text = Text(title)
        self.tone = tone
        self.filled = filled
    }

    public init(verbatim title: String, tone: ZBadgeTone = .neutral, filled: Bool = false) {
        self.text = Text(verbatim: title)
        self.tone = tone
        self.filled = filled
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZMetrics.tagRadius, style: .continuous)
        text
            .zMono(.tag)
            .tracking(0.3)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background { shape.fill(filled ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(Color.clear)) }
            .overlay { shape.strokeBorder(border, lineWidth: ZMetrics.hairline) }
            .fixedSize()
    }

    @Environment(\.zAccent) private var accent

    private var tint: Color {
        switch tone {
        case .neutral: return ZColor.t3
        case .accent: return accent.color
        case .success: return ZTokens.Colors.screenGreen
        case .warning: return ZTokens.Colors.screenAmber
        case .danger: return ZTokens.Colors.screenRed
        }
    }

    private var foreground: Color {
        tone == .neutral ? ZColor.t3 : tint
    }

    private var border: Color {
        tone == .neutral ? ZTokens.Colors.screenT4 : tint.opacity(0.45)
    }
}

#if DEBUG
private struct ZBadgeSample: View {
    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ZBadge("覆写", tone: .accent)
            ZBadge("订阅")
            ZBadge("域名")
            ZBadge(verbatim: "VLESS")
            ZBadge("已拦截", tone: .danger, filled: true)
            ZBadge("正常", tone: .success)
            ZBadge("将到期", tone: .warning)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZBadgeSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZBadgeSample() } }
#Preview("强调色") { ZAccentMatrix { ZBadge("覆写", tone: .accent) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) {
    ZBadge("覆写", tone: .accent)
    ZBadge("域名")
} }

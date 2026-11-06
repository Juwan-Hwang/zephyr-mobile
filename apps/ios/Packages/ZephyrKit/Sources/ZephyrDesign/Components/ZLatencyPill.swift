// 延迟读数（原型 `.vr .ms`：等宽 13、右对齐、最小宽 52；`.ms.u` 未测 —、`···` 检测中、`.ms.w` 高延迟黄色）。
// 颜色按 ZTokens.LatencyThreshold 分档：<80 good / 80–199 fair(黄) / 200–399 poor(橙) / ≥400 或超时 bad(红)。
// text = 列表里的纯文字；pill = 带 14% 底色的胶囊（详情、小组件）。

import SwiftUI

public enum ZLatencyStyle: Sendable {
    case text, pill
}

public struct ZLatencyPill: View {
    private let ms: Int?
    private let isTesting: Bool
    private let style: ZLatencyStyle
    @ScaledMetric(relativeTo: .footnote) private var minWidth: CGFloat = ZMetrics.latencyColumn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - ms: 毫秒；`nil` = 未检测，`-1`（或任意负数）= 超时。与 `ZTokens.LatencyThreshold.color(_:)` 约定一致。
    ///   - isTesting: 正在检测（显示 “···”）。
    public init(ms: Int?, isTesting: Bool = false, style: ZLatencyStyle = .text) {
        self.ms = ms
        self.isTesting = isTesting
        self.style = style
    }

    public var body: some View {
        Text(verbatim: display)
            .zMono(.body)
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : ZMotion.standard, value: display)
            .modifier(ZLatencyChrome(style: style, color: color, minWidth: minWidth))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken))
    }

    private var display: String {
        if isTesting { return "···" }
        guard let ms else { return "—" }
        if ms < 0 { return "超时" }
        return "\(ms) ms"
    }

    private var spoken: String {
        if isTesting { return "延迟检测中" }
        guard let ms else { return "延迟未检测" }
        if ms < 0 { return "延迟超时" }
        return "延迟 \(ms) 毫秒"
    }

    private var color: Color {
        if isTesting || ms == nil { return ZTokens.Colors.borderStrong }
        return ZTokens.LatencyThreshold.color(ms)
    }
}

private struct ZLatencyChrome: ViewModifier {
    let style: ZLatencyStyle
    let color: Color
    let minWidth: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .text:
            content.frame(minWidth: minWidth, alignment: .trailing)
        case .pill:
            content
                .padding(.horizontal, ZTokens.Space.n3)
                .padding(.vertical, ZTokens.Space.n1 / 2)
                .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        }
    }
}

#if DEBUG
private struct ZLatencySample: View {
    var body: some View {
        ForEach([38, 120, 260, 407, -1], id: \.self) { ms in
            HStack {
                Text(verbatim: "东京 03").zType(.body)
                Spacer()
                ZLatencyPill(ms: ms)
                ZLatencyPill(ms: ms, style: .pill)
            }
        }
        HStack {
            ZLatencyPill(ms: nil)
            ZLatencyPill(ms: nil, isTesting: true)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZLatencySample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZLatencySample() } }
#Preview("强调色") { ZAccentMatrix { ZLatencyPill(ms: 64, style: .pill) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZLatencySample() } }

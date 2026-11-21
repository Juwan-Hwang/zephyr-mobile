// 延迟读数（原型 `.vr .ms`：等宽 13、右对齐、最小宽 52；`.ms.u` 未测 —、`···` 检测中、`.ms.w` 高延迟黄色）。
// 颜色按 ZTokens.LatencyThreshold（tokens/mobile.json latency，按原型克制配色）：<200 ms 中性次级灰，≥200 ms 琥珀，
// 超时（负数）红并写“超时”；未测 “—” 与检测中 “···” 用 latency.unknown（= t3，契约 §18.b / 规范 §9.1 不用 t4）。不再是红黄绿四档。
// text = 列表里的纯文字；pill = 带 14% 底色的胶囊（详情、小组件）。

import SwiftUI
import ZephyrKit

public enum ZLatencyStyle: Sendable {
    case text, pill
}

public struct ZLatencyPill: View {
    private let ms: Int?
    private let isTesting: Bool
    private let style: ZLatencyStyle
    private let maxFontSize: CGFloat?
    private let columnWidth: CGFloat?
    @ScaledMetric(relativeTo: .footnote) private var minWidth: CGFloat = ZMetrics.latencyColumn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zStaticRendering) private var still

    /// - Parameters:
    ///   - ms: 毫秒；`nil` = 未检测，`-1`（或任意负数）= 超时。与 `ZTokens.LatencyThreshold.color(_:)` 约定一致。
    ///   - isTesting: 正在检测（显示 “···”）。
    public init(ms: Int?, isTesting: Bool = false, maxFontSize: CGFloat? = nil,
                columnWidth: CGFloat? = nil, style: ZLatencyStyle = .text) {
        self.maxFontSize = maxFontSize
        self.columnWidth = columnWidth
        self.ms = ms
        self.isTesting = isTesting
        self.style = style
    }

    public var body: some View {
        Text(verbatim: display)
            .modifier(ZMonoModifier(.body, weight: .regular, maxSize: maxFontSize))
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition((reduceMotion || still) ? .identity : .numericText())
            .animation((reduceMotion || still) ? nil : ZMotion.standard, value: display)
            .modifier(ZLatencyChrome(style: style, color: color, minWidth: columnWidth ?? minWidth))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken))
    }

    private var display: String {
        if isTesting { return "···" }
        guard let ms else { return "—" }
        if ms < 0 { return ZL.tr("超时") }
        return "\(ms) ms"
    }

    private var spoken: String {
        if isTesting { return ZL.tr("延迟检测中") }
        guard let ms else { return ZL.tr("未测") }
        if ms < 0 { return ZL.tr("延迟超时") }
        let value = ZL.f("延迟 %lld 毫秒", Int64(ms))
        return ms >= ZTokens.LatencyThreshold.slow ? value + ZL.tr("，") + ZL.tr("较慢") : value
    }

    /// latency.unknown（= t3），增强对比度下与 ZColor.t3 同步加深。
    private static let unknown = ZColor.boosted(ZTokens.Colors.latencyUnknown, by: 0.30)

    private var color: Color {
        if isTesting || ms == nil { return Self.unknown }
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

#if DEBUG
#Preview("深色") { ZPreviewCanvas { ZLatencySample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZLatencySample() } }
#Preview("强调色") { ZAccentMatrix { ZLatencyPill(ms: 64, style: .pill) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZLatencySample() } }
#endif

// 进度条（原型 `.bar` 2 高订阅用量、`.bar.warn` 黄色；`.meter` 4 高分段存储条：节点 / 规则 / 可用）。
// 宽度变化 320ms spring；Reduce Motion 下直接跳。

import SwiftUI

public enum ZProgressTone: Sendable {
    /// 原型默认 --t3/--t2 灰
    case neutral
    case accent
    case warning
    case danger
}

public enum ZProgressThickness: Sendable {
    /// 2pt（订阅卡用量）
    case thin
    /// 4pt（存储条）
    case regular

    var height: CGFloat { self == .thin ? ZMetrics.barThin : ZMetrics.barRegular }
}

/// 分段进度的一段。
public struct ZProgressSegment: Identifiable, Sendable {
    public let id: Int
    public let fraction: Double
    public let tone: ZProgressTone

    public init(id: Int, fraction: Double, tone: ZProgressTone) {
        self.id = id
        self.fraction = fraction
        self.tone = tone
    }
}

public struct ZProgressBar: View {
    private let segments: [ZProgressSegment]
    private let thickness: ZProgressThickness
    private let label: LocalizedStringKey?
    @Environment(\.zAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 单值进度：`value` 0...1。
    public init(value: Double, tone: ZProgressTone = .neutral, thickness: ZProgressThickness = .thin, label: LocalizedStringKey? = nil) {
        self.segments = [ZProgressSegment(id: 0, fraction: value, tone: tone)]
        self.thickness = thickness
        self.label = label
    }

    /// 分段进度：各段 fraction 之和 ≤ 1，按顺序从左到右排列。
    public init(segments: [ZProgressSegment], thickness: ZProgressThickness = .regular, label: LocalizedStringKey? = nil) {
        self.segments = segments
        self.thickness = thickness
        self.label = label
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(color(segment.tone))
                        .frame(width: proxy.size.width * clamp(segment.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: thickness.height)
        .background(ZTokens.Colors.screenHl)
        .clipShape(Capsule(style: .continuous))
        .animation(reduceMotion ? nil : ZMotion.slow, value: segments.map(\.fraction))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { Text($0) } ?? Text("进度"))
        .accessibilityValue(Text(verbatim: "\(Int((clamp(segments.reduce(0) { $0 + $1.fraction }) * 100).rounded()))%"))
    }

    private func clamp(_ v: Double) -> CGFloat {
        CGFloat(min(max(v.isFinite ? v : 0, 0), 1))
    }

    private func color(_ tone: ZProgressTone) -> Color {
        switch tone {
        case .neutral: return thickness == .thin ? ZTokens.Colors.screenT3 : ZTokens.Colors.screenT2
        case .accent: return accent.color
        case .warning: return ZTokens.Colors.screenAmber
        case .danger: return ZTokens.Colors.screenRed
        }
    }
}

#if DEBUG
private struct ZProgressSample: View {
    var body: some View {
        ZProgressBar(value: 0.56, label: "Nebula Cloud 用量")
        ZProgressBar(value: 0.88, tone: .warning, label: "Orbit 用量")
        ZProgressBar(segments: [
            ZProgressSegment(id: 0, fraction: 0.27, tone: .accent),
            ZProgressSegment(id: 1, fraction: 0.36, tone: .neutral),
        ], label: "存储")
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZProgressSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZProgressSample() } }
#Preview("强调色") { ZAccentMatrix { ZProgressBar(value: 0.4, tone: .accent, thickness: .regular) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZProgressSample() } }

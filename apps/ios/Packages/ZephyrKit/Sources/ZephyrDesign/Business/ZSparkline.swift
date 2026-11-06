// 流量曲线（原型 `.wind canvas`：下载蓝 1.5pt 平滑曲线 + 自上而下渐隐的面积填充，左右边缘淡出）。
// 性能：单个 Canvas 绘制（Catmull-Rom → 三次贝塞尔），不随数据点数创建子视图；
// 视图是 Equatable，调用方加 `.equatable()` 后只有数据真的变了才重画。
// 平滑滚动：传 `scrollPhase`（0..<1，一格的比例）由 TimelineView 驱动左移，再在每个采样到来时把数组整体左移一格并归零，
// 不触发整页重绘（只有这个 Canvas 重画）。

import SwiftUI

public struct ZSparkline: View, Equatable {
    private let samples: [Double]
    private let maxValue: Double?
    private let color: Color
    private let lineWidth: CGFloat
    private let fill: Bool
    private let fadesEdges: Bool
    private let scrollPhase: Double
    private let tension: Double
    private let label: LocalizedStringKey?

    /// - Parameters:
    ///   - samples: 按时间从旧到新的采样值（任意单位，如 bytes/s）。少于 2 个点不画。
    ///   - maxValue: 纵轴上限；nil 时取 max(samples) × 1.15 留出顶部余量。
    ///   - color: 线色，默认下载蓝 `ZTokens.Colors.colorDownload`。
    ///   - scrollPhase: 0..<1，整体向左平移的格数比例（用于逐帧平滑滚动）。
    ///   - tension: Catmull-Rom 张力，1 = 标准，0 = 折线。
    ///   - label: VoiceOver 名称；nil 表示纯装饰（读数已由 ZTrafficStat 提供）。
    public init(samples: [Double],
                maxValue: Double? = nil,
                color: Color = ZTokens.Colors.colorDownload,
                lineWidth: CGFloat = 1.5,
                fill: Bool = true,
                fadesEdges: Bool = true,
                scrollPhase: Double = 0,
                tension: Double = 1,
                label: LocalizedStringKey? = nil) {
        self.samples = samples
        self.maxValue = maxValue
        self.color = color
        self.lineWidth = lineWidth
        self.fill = fill
        self.fadesEdges = fadesEdges
        self.scrollPhase = scrollPhase
        self.tension = tension
        self.label = label
    }

    public static func == (lhs: ZSparkline, rhs: ZSparkline) -> Bool {
        lhs.samples == rhs.samples && lhs.maxValue == rhs.maxValue && lhs.color == rhs.color
            && lhs.lineWidth == rhs.lineWidth && lhs.fill == rhs.fill && lhs.fadesEdges == rhs.fadesEdges
            && lhs.scrollPhase == rhs.scrollPhase && lhs.tension == rhs.tension
    }

    public var body: some View {
        Canvas { context, size in
            guard samples.count > 1, size.width > 0, size.height > 0 else { return }
            let points = Self.points(samples, in: size, maxValue: maxValue, phase: scrollPhase, inset: lineWidth)
            let line = Self.smoothPath(points, tension: tension, height: size.height)
            if fill, let first = points.first, let last = points.last {
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.addLine(to: CGPoint(x: first.x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .mask {
            if fadesEdges {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            } else {
                Rectangle()
            }
        }
        .accessibilityHidden(label == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { Text($0) } ?? Text(verbatim: ""))
    }

    // MARK: - 几何（纯函数，便于单测）

    static func points(_ samples: [Double], in size: CGSize, maxValue: Double?, phase: Double, inset: CGFloat) -> [CGPoint] {
        let peak = samples.max() ?? 0
        let top = max(maxValue ?? peak * 1.15, .ulpOfOne)
        let step = size.width / CGFloat(max(samples.count - 1, 1))
        let usable = max(size.height - inset * 2, 1)
        return samples.enumerated().map { i, v in
            let clamped = min(max(v.isFinite ? v : 0, 0), top)
            let x = (CGFloat(i) - CGFloat(phase)) * step
            let y = inset + usable * (1 - CGFloat(clamped / top))
            return CGPoint(x: x, y: y)
        }
    }

    /// Catmull-Rom 样条转三次贝塞尔；控制点纵向夹在 [0, height] 内，避免过冲到底线以下。
    static func smoothPath(_ p: [CGPoint], tension: Double, height: CGFloat) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        guard p.count > 2, tension > 0 else {
            p.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        let k = CGFloat(tension) / 6
        func clampY(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x, y: min(max(pt.y, 0), height)) }
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = p[min(i + 2, p.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k)
            path.addCurve(to: p2, control1: clampY(c1), control2: clampY(c2))
        }
        return path
    }
}

#if DEBUG
private enum ZSparklineDemo {
    /// 确定性示例数据（不用随机数，快照稳定）。
    static let samples: [Double] = (0..<60).map { i in
        let t = Double(i)
        return 2.4 + sin(t * 0.37) * 0.9 + sin(t * 1.3) * 0.45 + (i % 17 == 0 ? 1.2 : 0)
    }
}

private struct ZSparklineLive: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZSparkline(samples: ZSparklineDemo.samples, scrollPhase: t.truncatingRemainder(dividingBy: 1))
                .equatable()
                .frame(height: 96)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSparkline(samples: ZSparklineDemo.samples).frame(height: 96) } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSparkline(samples: ZSparklineDemo.samples).frame(height: 96) } }
#Preview("强调色") { ZAccentMatrix { ZSparkline(samples: ZSparklineDemo.samples, color: ZTokens.Colors.colorUpload).frame(height: 60) } }
#Preview("AX5 · 滚动") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSparklineLive() } }

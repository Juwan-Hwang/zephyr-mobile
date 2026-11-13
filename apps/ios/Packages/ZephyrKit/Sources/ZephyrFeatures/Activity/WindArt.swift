// 今日卡片的生成式流线（原型 index.html windArt()，`.cart` 大图版）。
//
// 移植要点（原型画布是 2× 像素，这里全部换算成 pt）：
//   - 伪随机：rs = seed·9301；rnd = (rs·9301 + 49297) mod 233280 / 233280（同序消费：起点 y、长度、透明度、线宽）
//   - 线数 N = 150 + (2W·2H)/5000；起点 x = −10pt、y = H·(0.15 + 0.7·rnd)；最多 60 + 90·rnd 步，每步 3.2pt
//   - 方向 a = sin(x/W·3.1 + sd + t·0.25)·0.55 + cos(y/H·4.3 − sd·0.7 + t·0.18)·0.35 − 0.08
//   - 描边：左下 → 右上的线性渐变（色标见 TodayTheme.strokes），线宽 0.4 + 1.1·rnd pt，透明度 0.2 + 0.7·rnd
//   - t 每帧 +0.006（60fps ≈ 0.36/s）
// "图案由今天的流量生成"：每条线按起点所在的高度映射到 24 小时之一，透明度乘以该小时流量的相对值
// （0.35…1），流量多的时段线更亮更密；不含任何节点名或 IP。
//
// 线的静态参数（起点、长度、透明度、线宽）按尺寸缓存，每帧只重算路径。

import SwiftUI
import ZephyrDesign

struct WindArt: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        var y0: CGFloat
        var steps: Int
        var alpha: Double
        var width: CGFloat
    }

    static let prototypeSeed = 11
    /// 原型每帧 +0.006，按 60fps 换算成每秒。
    static let speed: Double = 0.006 * 60

    let size: CGSize
    let seed: Int
    let lines: [Line]

    init(size: CGSize, seed: Int = WindArt.prototypeSeed, hourly: [Int64] = []) {
        self.size = size
        self.seed = seed
        let w = Double(size.width), h = Double(size.height)
        let n = Int((150 + (2 * w) * (2 * h) / 5000).rounded())
        let peak = Double(hourly.max() ?? 0)
        var rs = seed * 9301
        func rnd() -> Double {
            rs = (rs * 9301 + 49297) % 233_280
            return Double(rs) / 233_280
        }
        var out: [Line] = []
        out.reserveCapacity(max(0, n))
        for _ in 0..<max(0, n) {
            let band = 0.15 + 0.7 * rnd()
            let steps = Int(60 + rnd() * 90)
            var alpha = 0.2 + 0.7 * rnd()
            let width = 0.4 + rnd() * 1.1
            if peak > 0, hourly.count == 24 {
                let hour = min(23, max(0, Int((band - 0.15) / 0.7 * 24)))
                alpha *= 0.35 + 0.65 * Double(hourly[hour]) / peak
            }
            out.append(Line(y0: CGFloat(h * band), steps: steps, alpha: alpha, width: CGFloat(width)))
        }
        lines = out
    }

    /// 第 t 时刻一条线的路径（原型同一公式）。
    func path(_ line: Line, t: Double) -> Path {
        let w = Double(size.width), h = Double(size.height)
        let sd = Double(seed)
        var x = -10.0, y = Double(line.y0)
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        for _ in 0..<line.steps {
            let a = sin(x / w * 3.1 + sd + t * 0.25) * 0.55 + cos(y / h * 4.3 - sd * 0.7 + t * 0.18) * 0.35 - 0.08
            x += cos(a) * 3.2
            y += sin(a) * 3.2
            p.addLine(to: CGPoint(x: x, y: y))
            if x > w + 10 { break }
        }
        return p
    }

    func draw(in ctx: inout GraphicsContext, theme: TodayTheme, t: Double) {
        let (c0, c1, c2) = theme.strokes
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: c0.opacity(0), location: 0),
                             .init(color: c0.opacity(0.7), location: 0.3),
                             .init(color: c1.opacity(0.85), location: 0.65),
                             .init(color: c2.opacity(0.6), location: 1)]),
            startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: size.width, y: 0))
        for line in lines {
            var c = ctx
            c.opacity = line.alpha
            c.stroke(path(line, t: t), with: shading, style: StrokeStyle(lineWidth: line.width, lineCap: .round))
        }
    }
}

/// 按尺寸缓存线的静态参数。Canvas 可能在后台线程渲染，所以用锁保护（不参与 SwiftUI 观察）。
final class WindArtCache: @unchecked Sendable {
    private let lock = NSLock()
    private var art: WindArt?
    private var hourly: [Int64] = []

    func art(for size: CGSize, hourly: [Int64]) -> WindArt {
        lock.lock(); defer { lock.unlock() }
        if let a = art, a.size == size, self.hourly == hourly { return a }
        let a = WindArt(size: size, hourly: hourly)
        art = a
        self.hourly = hourly
        return a
    }
}

/// 流线画布。`animated` 为 false（Reduce Motion / ImageRenderer 导出）时不挂 TimelineView，直接画 t 时刻的一帧。
@MainActor
struct WindArtCanvas: View {
    let theme: TodayTheme
    var hourly: [Int64] = []
    var animated = true
    var t: Double = 0

    @State private var cache = WindArtCache()
    @State private var start = Date()
    /// 快照渲染：不挂 TimelineView，固定画 t 时刻（否则帧随墙钟变化，参考图对不上）。
    @Environment(\.zStaticRendering) private var still

    var body: some View {
        Group {
            if animated && !still {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    artFrame(t: t + tl.date.timeIntervalSince(start) * WindArt.speed, asynchronous: true)
                }
            } else {
                artFrame(t: t, asynchronous: false)
            }
        }
        .accessibilityHidden(true)
    }

    /// 渲染闭包只捕获值类型与加锁的缓存，不读 @State / 环境。
    private func artFrame(t: Double, asynchronous: Bool) -> some View {
        let cache = self.cache
        let pal = theme
        let hours = hourly
        return Canvas(rendersAsynchronously: asynchronous) { ctx, size in
            cache.art(for: size, hourly: hours).draw(in: &ctx, theme: pal, t: t)
        }
    }
}

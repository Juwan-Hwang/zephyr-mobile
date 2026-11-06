// 首页全宽流量曲线（原型 #cv "wind"）。
//
//  - Canvas 绘制，TimelineView(.animation) 驱动 60/120fps：样本 1 Hz 到达，曲线在两个样本之间匀速左移，
//    曲线头沿最后一段平滑插值，看起来是连续流动而不是每秒跳一格。
//  - 只有本视图读取 TrafficStore；首页其余部分不随流量刷新重算。
//  - 未连接：底部一条虚线（原型 setLineDash([2,8])），暂停时间线。连接时振幅 0→1 缓入。
//  - Reduce Motion：暂停逐帧时间线，每个样本到达时直接重绘（无滚动插值）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct TrafficChart: View {
    let store: TrafficStore
    let isOn: Bool

    /// 可见样本数（≈ 1 分钟）。
    static let visible = 60
    /// 归一化看的窗口（比可见更宽，峰值滑出屏幕时不会突然缩放）。环形缓冲容量 300 ≥ 120。
    static let scaleWindow = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var onSince: TimeInterval?

    var body: some View {
        // 读一次 latest：Reduce Motion（时间线暂停）时样本到达也能触发重绘；只重算本小视图。
        let _ = store.latest?.at
        TimelineView(.animation(minimumInterval: nil, paused: !isOn || reduceMotion)) { _ in
            // 在主线程取值快照，Canvas 渲染闭包只接触值类型。
            let window = store.ring.suffix(Self.scaleWindow)
            let lo = Double(window.map(\.down).min() ?? 0), hi = Double(window.map(\.down).max() ?? 1)
            let snap = Snapshot(points: Array(window.suffix(Self.visible + 2)),
                                lo: lo * 0.92, hi: max(hi * 1.04, lo * 0.92 + 1),
                                arrival: store.latestArrival,
                                clock: ProcessInfo.processInfo.systemUptime)
            Canvas { ctx, size in
                draw(in: &ctx, size: size, snap: snap)
            }
        }
        .onChange(of: isOn, initial: true) { _, on in
            onSince = on ? ProcessInfo.processInfo.systemUptime : nil
        }
        .accessibilityHidden(true)
    }

    // MARK: 绘制

    private struct Snapshot {
        var points: [RatePoint]
        /// 归一化区间（按 120 点窗口的最小/最大值，留出上下余量）
        var lo: Double
        var hi: Double
        var arrival: TimeInterval
        var clock: TimeInterval
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, snap: Snapshot) {
        let w = size.width, h = size.height
        let baseY = h * 0.94
        let clock = snap.clock
        guard isOn, snap.points.count >= 2 else {
            drawIdle(in: &ctx, w: w, y: baseY)
            return
        }

        // 振幅缓入（0.6s ease-out）
        let amp: CGFloat = {
            guard !reduceMotion, let s = onSince else { return 1 }
            let t = min(1, max(0, (clock - s) / 0.6))
            return CGFloat(1 - pow(1 - t, 3))
        }()

        // 两个样本之间的滚动进度
        let progress: CGFloat = reduceMotion ? 1 : CGFloat(min(1, max(0, clock - snap.arrival)))

        let pts = snap.points
        let dx = w / CGFloat(Self.visible - 2)
        let headX = w - dx * 0.5
        let n = pts.count

        // 原型：y = H·0.94 − v·H·0.42（v ∈ 0…1）
        func y(_ v: Int64) -> CGFloat {
            let t = (Double(v) - snap.lo) / (snap.hi - snap.lo)
            return baseY - CGFloat(min(1, max(0, t))) * h * 0.42 * amp
        }
        func x(_ i: Int) -> CGFloat { headX - CGFloat(n - 1 - i) * dx + (1 - progress) * dx }

        var line = Path()
        var fill = Path()
        let p0 = CGPoint(x: x(0), y: y(pts[0].down))
        line.move(to: p0)
        fill.move(to: CGPoint(x: p0.x, y: h))
        fill.addLine(to: p0)
        for i in 1..<n {
            let prev = CGPoint(x: x(i - 1), y: y(pts[i - 1].down))
            let cur = CGPoint(x: x(i), y: y(pts[i].down))
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            line.addQuadCurve(to: mid, control: prev)
            fill.addQuadCurve(to: mid, control: prev)
        }
        if let last = pts.last { line.addLine(to: CGPoint(x: x(n - 1), y: y(last.down))) }
        fill.addLine(to: CGPoint(x: x(n - 1), y: y(pts[n - 1].down)))
        fill.addLine(to: CGPoint(x: x(n - 1), y: h))
        fill.closeSubpath()

        // 曲线头：沿最后一段在 headX 处插值
        let a = pts[n - 2], b = pts[n - 1]
        let headY = y(a.down) + (y(b.down) - y(a.down)) * progress

        let down = ZTokens.Colors.colorDownload
        let tail = ZTokens.Palette.sky400

        var clipped = ctx
        clipped.clip(to: Path(CGRect(x: 0, y: 0, width: headX, height: h)))
        clipped.opacity = Double(amp)
        clipped.fill(fill, with: .linearGradient(
            Gradient(colors: [down.opacity(0.20), down.opacity(0)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        clipped.stroke(line, with: .linearGradient(
            Gradient(stops: [.init(color: down.opacity(0), location: 0),
                             .init(color: down.opacity(0.9), location: 0.25),
                             .init(color: tail, location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // 头部光点（Reduce Motion 下不画光晕）
        var head = ctx
        head.opacity = Double(amp)
        if !reduceMotion {
            head.fill(Path(ellipseIn: CGRect(x: headX - 8, y: headY - 8, width: 16, height: 16)),
                      with: .color(tail.opacity(0.18)))
        }
        head.fill(Path(ellipseIn: CGRect(x: headX - 3, y: headY - 3, width: 6, height: 6)),
                  with: .color(scheme == .dark ? .white : down))
    }

    private func drawIdle(in ctx: inout GraphicsContext, w: CGFloat, y: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: w, y: y))
        ctx.stroke(p, with: .color(ZTokens.Colors.borderPrimary),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
    }
}

#Preview("曲线 · 已连接") {
    let model = AppModel.preview(connected: true)
    return TrafficChart(store: model.traffic, isOn: true)
        .frame(height: 150)
        .task { model.start() }
        .zPageBackground()
}

#Preview("曲线 · 未连接") {
    TrafficChart(store: TrafficStore(), isOn: false)
        .frame(height: 150)
        .zPageBackground()
}

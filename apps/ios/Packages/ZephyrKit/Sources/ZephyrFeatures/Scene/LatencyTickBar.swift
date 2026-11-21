// LatencyTickBar — 场景 sheet 候选列表顶部的延迟刻度条（规范 §9.6，设计评审 J-6，Halide 式）。
//
//   200 ms
//   ┊ ╷╷ ╷ ╷┃╷  ╷   ╷              超时 2
//
// 横轴 0–600 ms 线性（> 600 贴右端）；每个候选一根短刻（1×6pt，t3；≥ 200 ms 用 screen.amber），
// 200 ms 处长刻（1×12pt，t2，latency.threshold-slow）并在上方写「200 ms」；当前出口节点短刻加高到 10pt、accent base。
// 超时不画，计入右侧「超时 n」（red-text，n = 0 不显示）；未测不画。只用于场景 sheet（候选 ≤ 几十个）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct LatencyTickBar: View {
    let candidates: [NodeSummary]
    let selectedId: NodeId?

    nonisolated static let rangeMs: Double = 600
    @Environment(\.zAccent) private var accent

    private var measured: [(id: NodeId, ms: Int)] {
        var out: [(id: NodeId, ms: Int)] = []
        for n in candidates {
            if let ms = n.latencyMs, ms >= 0 { out.append((id: n.id, ms: Int(ms))) }
        }
        return out
    }
    private var timeouts: Int { candidates.filter { ($0.latencyMs ?? 0) < 0 }.count }
    private var underThreshold: Int { measured.filter { $0.ms < ZTokens.LatencyThreshold.slow }.count }

    var body: some View {
        HStack(alignment: .bottom, spacing: ZTokens.Space.n4) {
            GeometryReader { geo in
                let w = geo.size.width
                let x200 = Self.x(for: ZTokens.LatencyThreshold.slow, width: w)
                let pts = measured, sel = selectedId, slow = ZTokens.LatencyThreshold.slow
                let t2 = ZColor.t2, t3 = ZColor.t3, amber = ZTokens.Colors.screenAmber, accentColor = accent.adaptive
                let short = Self.shortTick, tall = Self.selectedTick, long = Self.longTick
                ZStack(alignment: .bottomLeading) {
                    Text(verbatim: "\(ZTokens.LatencyThreshold.slow) ms")
                        .zType(.caption, monospacedDigits: true)
                        .foregroundStyle(ZColor.t3)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in d.width / 2 - x200 }
                        .alignmentGuide(.bottom) { d in d.height + Self.longTick + ZTokens.Space.n1 }
                    Canvas { ctx, size in
                        let h = size.height
                        // 200 ms 长刻
                        ctx.fill(Path(CGRect(x: x200 - 0.5, y: h - long, width: 1, height: long)), with: .color(t2))
                        // 未选中的在下，选中的最后画（盖在上面）
                        for m in pts where m.id != sel {
                            let x = Self.x(for: m.ms, width: size.width)
                            ctx.fill(Path(CGRect(x: x - 0.5, y: h - short, width: 1, height: short)),
                                     with: .color(m.ms >= slow ? amber : t3))
                        }
                        if let s = pts.first(where: { $0.id == sel }) {
                            let x = Self.x(for: s.ms, width: size.width)
                            ctx.fill(Path(CGRect(x: x - 0.5, y: h - tall, width: 1, height: tall)), with: .color(accentColor))
                        }
                    }
                    .frame(height: Self.longTick)
                }
                .frame(width: w, height: geo.size.height, alignment: .bottomLeading)
            }
            .frame(height: Self.height)
            if timeouts > 0 {
                Text(verbatim: ZL.s("超时 %@", "\(timeouts)"))
                    .zType(.caption, monospacedDigits: true)
                    .foregroundStyle(ZTokens.Colors.screenRedText)
                    .fixedSize()
            }
        }
        .environment(\.layoutDirection, .leftToRight)   // 数轴总是从左到右
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ZL.s("%1$@ 个候选，%2$@ 个低于 200 毫秒，超时 %3$@",
                                                "\(candidates.count)", "\(underThreshold)", "\(timeouts)")))
    }

    static let shortTick: CGFloat = 6
    static let selectedTick: CGFloat = 10
    static let longTick: CGFloat = 12
    /// 刻度区 12pt + 上方「200 ms」一行。
    static let height: CGFloat = 30

    /// 0–600 ms 线性映射到宽度（两端各留 0.5pt，> 600 贴右端）。
    nonisolated static func x(for ms: Int, width: CGFloat) -> CGFloat {
        let t = min(max(Double(ms), 0), rangeMs) / rangeMs
        return 0.5 + (width - 1) * CGFloat(t)
    }
}

#if DEBUG
#Preview {
    let ms: [Int32?] = [38, 64, 92, 120, 150, 188, 210, 260, 407, 720, -1, -1, nil]
    let nodes = ms.enumerated().map { i, m in
        NodeSummary(id: NodeId(i), name: "节点 \(i)", region: "JP", protocol: "", latencyMs: m)
    }
    return LatencyTickBar(candidates: nodes, selectedId: 2)
        .padding()
        .zPageBackground()
}
#endif

// 场景行的小部件：检测中进度条（原型 scan 变体）与"左右滑动以切换地区"提示（原型 `.coach`）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

/// 检测中：2pt 轨道上来回移动的强调色片段。契约 v0 没有检测进度（tested/total），所以是不确定进度；
/// 契约补上后改为确定进度（见 NOTES-H.md）。Reduce Motion 下静止显示 30%。
@MainActor
struct ProbeBar: View {
    /// 有扫描进度时为确定进度（原型 scan：`.bar i` width = done/total）；nil = 来回滑动的不定进度。
    var fraction: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zStaticRendering) private var still
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(ZTokens.Colors.screenHl2)
                if let fraction {
                    Capsule().fill(ZAccentStyle())
                        .frame(width: w * CGFloat(fraction))
                        .animation((reduceMotion || still) ? nil : .easeOut(duration: ZTokens.Time.slow), value: fraction)
                } else {
                    Capsule().fill(ZAccentStyle())
                        .frame(width: w * 0.3)
                        .offset(x: reduceMotion ? 0 : phase * w * 0.7)
                }
            }
        }
        .frame(height: HMetrics.barThin)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(ZTokens.Easing.easeInOut(duration: ZTokens.Time.slow * 3).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityLabel(Text("检测中"))
    }
}

/// 一次性引导提示：强调色小字，轻微左右晃动（Reduce Motion 下静止）。
@MainActor
struct CoachHint: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudge = false

    var body: some View {
        Text(verbatim: text)
            .zType(.caption)
            .foregroundStyle(ZAccentTextStyle())
            .padding(.horizontal, ZTokens.Space.n3)
            .background(Capsule().fill(ZCardFill()).background(Capsule().fill(ZPage.background)))
            .offset(x: nudge ? ZTokens.Space.n1 : -ZTokens.Space.n1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(ZTokens.Easing.easeInOut(duration: ZTokens.Time.slow * 4).repeatForever(autoreverses: true)) {
                    nudge = true
                }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: ZTokens.Space.n6) {
        ProbeBar().frame(width: HMetrics.probeBarWidth)
        CoachHint(text: ZL.tr("左右滑动以切换地区"))
    }
    .padding()
    .zPageBackground()
}
#endif

/// 首页迷你漏斗（规范 §9.3，设计评审 J-1）：全部 → 已测速 → 可连通 → 低于 200 ms 四段水平细条，
/// 宽度按 log10(count + 1) 归一到 `HMetrics.miniFunnelWidth`，从左到右依次缩短；前三段 t3，最后一段 accent base，
/// 最后一段下方写 `underThreshold`（caption、t1、等宽数字）。数据取不到时调用方不画它，退回「N 个可用」。
@MainActor
struct MiniFunnel: View {
    let funnel: NodeFunnel

    var body: some View {
        let w = Self.widths(funnel)
        let lastX = w.dropLast().reduce(0, +) + CGFloat(w.count - 1) * HMetrics.miniFunnelGap
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            HStack(spacing: HMetrics.miniFunnelGap) {
                ForEach(w.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: HMetrics.miniFunnelBar / 2)
                        .fill(i == w.count - 1 ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZColor.t3))
                        .frame(width: w[i], height: HMetrics.miniFunnelBar)
                }
            }
            Text(verbatim: ZFormat.count(Int64(funnel.underThreshold)))
                .zType(.caption).monospacedDigit()
                .foregroundStyle(ZTokens.Colors.screenT1)
                .fixedSize()
                .padding(.leading, lastX)
        }
        .frame(width: HMetrics.miniFunnelWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spoken(funnel)))
    }

    /// 「可连通 {reachable}，低于 200 毫秒 {underThreshold}」。
    static func spoken(_ f: NodeFunnel) -> String {
        ZL.s("可连通 %1$@，低于 200 毫秒 %2$@", ZFormat.count(Int64(f.reachable)), ZFormat.count(Int64(f.underThreshold)))
    }

    /// 四段宽度：log10(count + 1) 按总和归一到总宽（扣掉段间距），每段至少 2pt 以便 0 也看得到位置。纯函数，便于单测。
    nonisolated static func widths(_ f: NodeFunnel, total: CGFloat = HMetrics.miniFunnelWidth,
                                   gap: CGFloat = HMetrics.miniFunnelGap, minimum: CGFloat = 2) -> [CGFloat] {
        let counts = [f.poolSize, f.tested, f.reachable, f.underThreshold]
        let logs = counts.map { log10(Double(max($0, 0)) + 1) }
        let sum = logs.reduce(0, +)
        let room = total - gap * CGFloat(counts.count - 1) - minimum * CGFloat(counts.count)
        guard sum > 0, room > 0 else { return Array(repeating: minimum, count: counts.count) }
        return logs.map { minimum + room * CGFloat($0 / sum) }
    }
}

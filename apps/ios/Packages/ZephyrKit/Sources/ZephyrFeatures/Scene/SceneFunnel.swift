// 场景漏斗（原型 `.funnel`）：每级一行"数字 · 条 · 说明"，条宽按数量对数比例，最后一级强调色。
// 出现时逐级从左展开（120ms 起、每级 +90ms）；Reduce Motion 下直接显示。

import SwiftUI
import ZephyrDesign

struct FunnelStep: Hashable, Identifiable {
    var count: Int
    var label: String
    var id: String { label }
}

@MainActor
struct SceneFunnel: View {
    let steps: [FunnelStep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let maxCount = max(1, steps.map(\.count).max() ?? 1)
        Grid(alignment: .leading, horizontalSpacing: ZTokens.Space.n4, verticalSpacing: ZTokens.Space.n3) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                let last = i == steps.count - 1
                GridRow {
                    Text(verbatim: "\(step.count)")
                        .zMono(.body)
                        .foregroundStyle(last ? ZTokens.Colors.screenT1 : ZTokens.Colors.screenT2)
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: ZTokens.Space.n4) {
                        Capsule()
                            .fill(last ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZKnobFill()))
                            .frame(width: barWidth(step.count, max: maxCount), height: HMetrics.funnelBar)
                            .scaleEffect(x: shown || reduceMotion ? 1 : 0.001, anchor: .leading)
                            .animation(reduceMotion ? nil : ZMotion.page.delay(0.12 + Double(i) * 0.09), value: shown)
                        Text(verbatim: step.label)
                            .zType(.footnote)
                            .foregroundStyle(last ? ZTokens.Colors.screenT2 : ZTokens.Colors.screenT3)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(step.label) \(step.count) 个"))
            }
        }
        .onAppear { shown = true }
    }

    /// 对数比例（1 → 最小宽 12，max → 200），与原型 58% / 30% / 13% / 6% 的观感一致。
    private func barWidth(_ n: Int, max m: Int) -> CGFloat {
        let minW = ZTokens.Space.n4, maxW: CGFloat = 200
        guard m > 1 else { return maxW }
        let t = log(Double(Swift.max(n, 1))) / log(Double(m))
        return minW + (maxW - minW) * CGFloat(t * t)
    }
}

#Preview {
    SceneFunnel(steps: [FunnelStep(count: 512, label: "全部"), FunnelStep(count: 138, label: "延迟低于 300 ms"),
                        FunnelStep(count: 27, label: "可访问 GPT"), FunnelStep(count: 9, label: "可访问 GPT、Claude 和 Gemini")])
        .padding()
        .zPageBackground()
}

// 场景行的小部件：检测中进度条（原型 scan 变体）与"左右滑动以切换地区"提示（原型 `.coach`）。

import SwiftUI
import ZephyrDesign

/// 检测中：2pt 轨道上来回移动的强调色片段。契约 v0 没有检测进度（tested/total），所以是不确定进度；
/// 契约补上后改为确定进度（见 NOTES-H.md）。Reduce Motion 下静止显示 30%。
@MainActor
struct ProbeBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(ZTokens.Colors.screenHl2)
                Capsule().fill(ZAccentStyle())
                    .frame(width: w * 0.3)
                    .offset(x: reduceMotion ? 0 : phase * w * 0.7)
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
            .foregroundStyle(ZAccentStyle())
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

#Preview {
    VStack(spacing: ZTokens.Space.n6) {
        ProbeBar().frame(width: HMetrics.probeBarWidth)
        CoachHint(text: "左右滑动以切换地区")
    }
    .padding()
    .zPageBackground()
}

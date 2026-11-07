// 今日用量柱状图：24 个小时桶，按最大值归一。Canvas 一次绘制，避免 24 个子视图。

import SwiftUI
import ZephyrDesign

struct UsageBars: View {
    var hourly: [Int64]
    var accent: Color

    var body: some View {
        Canvas { ctx, size in
            let buckets = hourly.isEmpty ? Array(repeating: Int64(0), count: 24) : hourly
            let maxValue = max(buckets.max() ?? 0, 1)
            let n = CGFloat(buckets.count)
            let gap = max(1, size.width / n * 0.35)
            let barWidth = max(1, (size.width - gap * (n - 1)) / n)
            let minHeight = barWidth * 0.8
            let gradient = Gradient(colors: [accent.opacity(0.55), accent])
            for (i, value) in buckets.enumerated() {
                let h = max(minHeight, size.height * CGFloat(Double(value) / Double(maxValue)))
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: size.height - h, width: barWidth, height: h)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous)
                ctx.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                                                     endPoint: CGPoint(x: rect.midX, y: rect.minY)))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    UsageBars(hourly: SharedState.prototype().usage.hourly, accent: ZTokens.Accent.blue.color)
        .frame(width: 130, height: 60)
        .padding()
        .background(ZTokens.Colors.screenS1)
}

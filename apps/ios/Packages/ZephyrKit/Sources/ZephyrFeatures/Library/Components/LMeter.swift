// LMeter — 用量条（原型 .meter：4pt 高、2pt 圆角，多段依次排列）。

import SwiftUI
import ZephyrDesign

struct LMeter: View {
    struct Segment: Identifiable {
        var fraction: Double
        var color: Color
        var id: Int
    }
    var segments: [Segment]

    /// 单段：fraction 0…1。
    init(fraction: Double, color: Color) {
        segments = [Segment(fraction: fraction, color: color, id: 0)]
    }

    init(segments: [(Double, Color)]) {
        self.segments = segments.enumerated().map { Segment(fraction: $0.element.0, color: $0.element.1, id: $0.offset) }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments) { s in
                    Rectangle()
                        .fill(s.color)
                        .frame(width: geo.size.width * min(1, max(0, s.fraction)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: ZTokens.Space.n1)
        .background(ZTokens.Colors.borderSubtle)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        LMeter(fraction: 0.57, color: ZTokens.Colors.textSecondary)
        LMeter(segments: [(0.31, ZTokens.Accent.blue.color), (0.46, ZTokens.Colors.textTertiary)])
    }
    .padding()
    .background(LStyle.pageBackground)
}

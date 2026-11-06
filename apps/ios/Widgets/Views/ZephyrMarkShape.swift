// Zephyr 标志（两片风叶）的矢量形状。路径取自 design/prototype/brand/app-icon.svg，
// SVG 圆弧已离线转成三次贝塞尔并归一化到 164×142 的标志框（scripts/svg_mark_to_swift.py）。
// 小组件、实时活动、灵动岛都用它：不依赖任何资源包，扩展与快照测试里同样可用。

import SwiftUI

struct ZephyrMarkShape: Shape {
    /// 宽 / 高
    static let aspectRatio: CGFloat = 164.0 / 142.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: p(0.97610, -0.00007))
        path.addLine(to: p(0.00884, -0.00007))
        path.addCurve(to: p(0.00006, 0.01014), control1: p(0.00398, -0.00003), control2: p(0.00006, 0.00453))
        path.addCurve(to: p(0.12988, 0.56915), control1: p(0.00155, 0.20618), control2: p(0.04623, 0.39856))
        path.addCurve(to: p(0.14110, 0.57261), control1: p(0.13216, 0.57367), control2: p(0.13717, 0.57522))
        path.addLine(to: p(0.97933, 0.01373))
        path.addCurve(to: p(0.98232, 0.00539), control1: p(0.98185, 0.01206), control2: p(0.98307, 0.00863))
        path.addCurve(to: p(0.97610, -0.00007), control1: p(0.98156, 0.00215), control2: p(0.97900, -0.00009))
        path.closeSubpath()
        path.move(to: p(0.02390, 1.00007))
        path.addLine(to: p(0.99116, 1.00007))
        path.addCurve(to: p(0.99994, 0.98986), control1: p(0.99602, 1.00003), control2: p(0.99994, 0.99547))
        path.addCurve(to: p(0.87012, 0.43085), control1: p(0.99845, 0.79382), control2: p(0.95377, 0.60144))
        path.addCurve(to: p(0.85890, 0.42739), control1: p(0.86784, 0.42633), control2: p(0.86283, 0.42478))
        path.addLine(to: p(0.02067, 0.98627))
        path.addCurve(to: p(0.01768, 0.99461), control1: p(0.01815, 0.98794), control2: p(0.01693, 0.99137))
        path.addCurve(to: p(0.02390, 1.00007), control1: p(0.01844, 0.99785), control2: p(0.02100, 1.00009))
        path.closeSubpath()
        return path
    }
}

/// 标志，按高度等比；颜色取 foregroundStyle。
struct WidgetMark: View {
    var body: some View {
        ZephyrMarkShape()
            .aspectRatio(ZephyrMarkShape.aspectRatio, contentMode: .fit)
            .accessibilityLabel("Zephyr")
    }
}

#Preview {
    WidgetMark()
        .frame(height: 40)
        .foregroundStyle(.white)
        .padding()
        .background(.black)
}

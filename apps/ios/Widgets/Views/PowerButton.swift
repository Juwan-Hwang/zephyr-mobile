// 小组件右上角的电源按钮（原型 shots/hs.png、index.html `.pw`：30pt 白色圆 + 黑色电源图标）。
// iOS 17 交互式小组件：Button(intent:) 直接执行 ConnectIntent。
// REVIEW-Q1 W-P2-6：视觉按原型缩小，触控区仍为 44pt —— 外层 44 框 + contentShape 承接点击，
// 再用负 padding 把布局占位还原成视觉尺寸，不挤压旁边的标志与大数字。

import AppIntents
import SwiftUI
import ZephyrDesign

struct PowerButton: View {
    var isOn: Bool

    /// 原型 `.pw` 30×30（hs.png 实测 60px@2x）。
    @ScaledMetric(relativeTo: .footnote) private var diameter: CGFloat = 30
    private var touch: CGFloat { max(ZTokens.Layout.touchMinIos, diameter) }

    var body: some View {
        Button(intent: ConnectIntent(value: !isOn)) {
            Image(systemName: "power")
                .zType(.footnote)
                .fontWeight(.bold)
                .foregroundStyle(isOn ? ZTokens.Colors.screenOnPrimary : ZTokens.Colors.screenT1)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(isOn ? ZTokens.Colors.screenPrimary : ZTokens.Colors.screenS3))
                .frame(width: touch, height: touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-(touch - diameter) / 2)
        .accessibilityLabel(isOn ? "断开 Zephyr" : "连接 Zephyr")
    }
}

#Preview {
    HStack(spacing: ZTokens.Space.n5) {
        PowerButton(isOn: true)
        PowerButton(isOn: false)
    }
    .padding()
    .background(ZTokens.Colors.screenS1)
}

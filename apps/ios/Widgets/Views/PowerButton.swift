// 小组件右上角的电源按钮（原型 shots/hs.png）。iOS 17 交互式小组件：Button(intent:) 直接执行 ConnectIntent。

import AppIntents
import SwiftUI
import ZephyrDesign

struct PowerButton: View {
    var isOn: Bool

    var body: some View {
        Button(intent: ConnectIntent(value: !isOn)) {
            Image(systemName: "power")
                .zType(.headline)
                .foregroundStyle(isOn ? ZTokens.Colors.bgElevated : ZTokens.Colors.textPrimary)
                .frame(width: ZTokens.Layout.touchMinIos, height: ZTokens.Layout.touchMinIos)
                .background(Circle().fill(isOn ? ZTokens.Colors.textPrimary : ZTokens.Colors.bgMuted))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "断开 Zephyr" : "连接 Zephyr")
    }
}

#Preview {
    HStack(spacing: ZTokens.Space.n5) {
        PowerButton(isOn: true)
        PowerButton(isOn: false)
    }
    .padding()
    .background(ZTokens.Colors.bgElevated)
}

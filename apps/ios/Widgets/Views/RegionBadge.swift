// 地区码方框徽标：[JP]。与 ZephyrDesign 的 ZFlag 视觉一致，但不依赖其初始化签名（扩展里保持零耦合）。

import SwiftUI
import ZephyrDesign

struct RegionBadge: View {
    var region: String
    var prominent = false

    var body: some View {
        Text(region.uppercased())
            .zType(.caption, monospacedDigits: true)
            .fontWeight(.semibold)
            .fontDesign(.monospaced)
            .foregroundStyle(prominent ? ZTokens.Colors.screenT1 : ZTokens.Colors.screenT2)
            .padding(.horizontal, ZTokens.Space.n1)
            .padding(.vertical, ZTokens.Space.n0 + 1)
            .overlay(
                RoundedRectangle(cornerRadius: ZTokens.Radius.control / 2, style: .continuous)
                    .strokeBorder(ZTokens.Colors.screenT4, lineWidth: 1)
            )
            .accessibilityLabel(Locale.current.localizedString(forRegionCode: region) ?? region)
    }
}

#Preview {
    HStack(spacing: ZTokens.Space.n3) {
        RegionBadge(region: "JP")
        RegionBadge(region: "HK")
        RegionBadge(region: "TW", prominent: true)
    }
    .padding()
    .background(ZTokens.Colors.screenS1)
}

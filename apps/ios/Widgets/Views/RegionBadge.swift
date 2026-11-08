// 地区码方框徽标：[JP]。规格与 ZephyrDesign 的 ZFlag(.small) 一致（REVIEW-Q1 W-P2-3）：
// 等宽 10/600、字距 .04em、18 高、最小宽 25、1pt hl2 细边框、圆角 5、t2 文字。
// ZMetrics 是 ZephyrDesign 内部常量，这里按 ZFlag 复制一份（扩展里不依赖 ZFlag 的初始化签名，保持零耦合）。
// VoiceOver 读地区名（“日本”），而不是逐字母。

import SwiftUI
import ZephyrDesign

struct RegionBadge: View {
    var region: String
    var prominent = false

    /// 与 ZFlag(.small) 同源的尺寸（原型 `.cc`：20 高 / 最小宽 28 / 圆角 5 / 字号 10.5，small 档 × 0.9）。
    private enum Spec {
        static let height: CGFloat = 20 * 0.9
        static let minWidth: CGFloat = 28 * 0.9
        static let radius: CGFloat = 5
        static let hairline: CGFloat = 1
        static let tracking: CGFloat = 10.5 * 0.04
    }

    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = Spec.height
    @ScaledMetric(relativeTo: .caption2) private var minWidth: CGFloat = Spec.minWidth

    var body: some View {
        let code = region.uppercased()
        Text(verbatim: code)
            .zMono(.tag, weight: .semibold)
            .tracking(Spec.tracking)
            .foregroundStyle(prominent ? ZTokens.Colors.screenT1 : ZColor.t2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ZTokens.Space.n1)
            .frame(minWidth: minWidth, minHeight: height)
            .overlay(
                RoundedRectangle(cornerRadius: Spec.radius, style: .continuous)
                    .strokeBorder(ZTokens.Colors.screenHl2, lineWidth: Spec.hairline)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.regionName(code)))
    }

    /// 地区码 → 本地化地区名；未知码按字母朗读（与 ZFlag 一致）。
    static func regionName(_ code: String) -> String {
        if let name = Locale.current.localizedString(forRegionCode: code), name != code {
            return name
        }
        return code.map(String.init).joined(separator: " ")
    }
}

#Preview {
    HStack(spacing: ZTokens.Space.n3) {
        RegionBadge(region: "JP")
        RegionBadge(region: "HK")
        RegionBadge(region: "TW", prominent: true)
        ZFlag("SG", size: .small)
    }
    .padding()
    .background(ZTokens.Colors.screenS1)
}

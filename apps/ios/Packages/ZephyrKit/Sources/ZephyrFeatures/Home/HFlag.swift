// 地区码方框徽标（原型 `.cc`：SF Mono 10.5/600、1px 边框、圆角 5）。
// 待替换：D 的 ZFlag 落地后换成 ZFlag（见 NOTES-H.md）。
// `ticking` = 左右滑动跨地区时的放大 + 强调色（原型 `.cc.tick`）。

import SwiftUI
import ZephyrDesign

struct HFlag: View {
    let region: String
    var ticking = false
    @ScaledMetric(relativeTo: .caption2) private var height = HMetrics.flagHeight
    @ScaledMetric(relativeTo: .caption2) private var minWidth = HMetrics.flagMinWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: region)
            .zMono(.flag, weight: .semibold)
            .tracking(0.4)
            .foregroundStyle(ticking ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZTokens.Colors.textSecondary))
            .padding(.horizontal, ZTokens.Space.n1)
            .frame(minWidth: minWidth, minHeight: height)
            .overlay {
                RoundedRectangle(cornerRadius: HMetrics.flagRadius, style: .continuous)
                    .strokeBorder(ticking ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZTokens.Colors.borderStrong),
                                  lineWidth: HMetrics.hairline)
            }
            .scaleEffect(ticking && !reduceMotion ? 1.18 : 1)
            .animation(ZMotion.micro, value: ticking)
            .accessibilityLabel(Text(verbatim: HRegionName.zh(region)))
    }
}

/// 地区码 → 中文名（VoiceOver 与指令 token 用）。覆盖原型 RG 的 15 个地区。
enum HRegionName {
    static let table: [String: String] = [
        "US": "美国", "JP": "日本", "HK": "香港", "SG": "新加坡", "TW": "台湾", "KR": "韩国", "DE": "德国",
        "GB": "英国", "NL": "荷兰", "FR": "法国", "CA": "加拿大", "AU": "澳大利亚", "IN": "印度", "BR": "巴西", "TR": "土耳其",
    ]
    static func zh(_ code: String) -> String { table[code.uppercased()] ?? code }
}

#Preview {
    HStack(spacing: ZTokens.Space.n3) {
        HFlag(region: "SG")
        HFlag(region: "JP", ticking: true)
        HFlag(region: "HK")
    }
    .padding()
    .zPageBackground()
}

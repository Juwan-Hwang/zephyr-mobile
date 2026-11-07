// 地区码方框徽标（原型 `.cc`：等宽 10.5/600、字距 .04em、20 高、最小宽 28、1px --hl2 细边框、圆角 5、t2 文字）。
// 不用 emoji 国旗：方框 + 地区码更克制、跨平台一致、在等宽列表里对齐。
// highlighted（原型 `.cc.tick`）：强调色 + 放大 1.18 的一次“跳动”，用于左右滑切换地区。
// VoiceOver 读地区名（Locale 本地化，如 “新加坡”），而不是逐字母。

import SwiftUI

public enum ZFlagSize: Sendable {
    /// 20pt 高（首页、场景、轨迹）
    case regular
    /// 18pt 高、9.5 号（小组件、紧凑行）
    case small
}

public struct ZFlag: View {
    private let code: String
    private let size: ZFlagSize
    private let isHighlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = ZMetrics.flagHeight
    @ScaledMetric(relativeTo: .caption2) private var minWidth: CGFloat = ZMetrics.flagMinWidth

    /// - Parameter code: ISO 3166-1 alpha-2（"SG"、"HK"、"JP"），大小写不限；也可以是 2–3 位自定义码。
    public init(_ code: String, size: ZFlagSize = .regular, isHighlighted: Bool = false) {
        self.code = code.uppercased()
        self.size = size
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        let scale: CGFloat = size == .small ? 0.9 : 1
        let shape = RoundedRectangle(cornerRadius: ZMetrics.flagRadius, style: .continuous)
        Text(verbatim: code)
            .zMono(size == .small ? .tag : .flag, weight: .semibold)
            .tracking(ZMetrics.monoFlag * 0.04)
            .foregroundStyle(isHighlighted ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZTokens.Colors.screenT2))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ZTokens.Space.n1)
            .frame(minWidth: minWidth * scale, minHeight: height * scale)
            .overlay {
                shape.strokeBorder(isHighlighted ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZTokens.Colors.screenHl2),
                                   lineWidth: ZMetrics.hairline)
            }
            .scaleEffect(isHighlighted && !reduceMotion ? 1.18 : 1)
            .animation(ZMotion.micro, value: isHighlighted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.regionName(code)))
    }

    /// 地区码 → 本地化地区名；未知码按字母朗读。
    static func regionName(_ code: String) -> String {
        if let name = Locale.current.localizedString(forRegionCode: code), name != code {
            return name
        }
        return code.map(String.init).joined(separator: " ")
    }
}

#if DEBUG
private struct ZFlagSample: View {
    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ForEach(["SG", "HK", "JP", "TW", "US", "KR"], id: \.self) { ZFlag($0) }
        }
        HStack(spacing: ZTokens.Space.n3) {
            ZFlag("JP")
            Text(verbatim: "东京 03").zType(.body)
            ZFlag("sg", size: .small)
            ZFlag("HK", isHighlighted: true)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZFlagSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZFlagSample() } }
#Preview("强调色") { ZAccentMatrix { ZFlag("HK", isHighlighted: true) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZFlagSample() } }

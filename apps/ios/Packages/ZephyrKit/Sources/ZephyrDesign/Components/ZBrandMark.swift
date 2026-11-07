// 品牌图形：标志（两片风叶）与 “Zephyr” 字标。来源 design/prototype/brand/app-lockup.svg，
// 以模板矢量图放在 Resources/Brand.xcassets（preserves-vector-representation），颜色取前景色。

import SwiftUI

public struct ZBrandMark: View {
    public enum Variant: Sendable {
        /// 仅标志，宽高比 164:142
        case mark
        /// 标志 + 字标，宽高比 625:142（首页左上 `.wmk`）
        case lockup
    }

    private let variant: Variant

    public init(_ variant: Variant = .lockup) {
        self.variant = variant
    }

    public var body: some View {
        Image(variant == .mark ? "ZephyrMark" : "ZephyrLockup", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel(Text(verbatim: "Zephyr"))
            .accessibilityAddTraits(.isImage)
    }
}

#Preview("深色") {
    ZPreviewCanvas {
        HStack(spacing: ZTokens.Space.n3) {
            ZStatusDot(isOn: true)
            ZBrandMark().frame(height: 15)
        }
        .foregroundStyle(ZTokens.Colors.screenT1)
        ZBrandMark(.mark).frame(height: 40).foregroundStyle(ZAccentStyle())
    }
}

#Preview("浅色") {
    ZPreviewCanvas(scheme: .light) {
        ZBrandMark().frame(height: 15).foregroundStyle(ZTokens.Colors.screenT1)
    }
}

#Preview("强调色") {
    ZAccentMatrix {
        ZBrandMark(.mark).frame(height: 28).foregroundStyle(ZAccentStyle())
    }
}

#Preview("AX5") {
    ZPreviewCanvas(dynamicType: .accessibility5) {
        ZBrandMark().frame(height: 15).foregroundStyle(ZTokens.Colors.screenT1)
    }
}

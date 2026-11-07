// 设置分组（原型 `.grp`：左右 16 外边距由页面负责；圆角卡片、1px 细边框、overflow hidden）。
// 可选分组标题（ZSectionHeader）与底部说明（`.ft` 12.5 t3）。行之间请自行放 ZDivider()。

import SwiftUI

public struct ZSettingsGroup<Content: View>: View {
    private let header: LocalizedStringKey?
    private let headerTrailing: String?
    private let footer: LocalizedStringKey?
    private let content: Content

    public init(_ header: LocalizedStringKey? = nil,
                trailing headerTrailing: String? = nil,
                footer: LocalizedStringKey? = nil,
                @ViewBuilder content: () -> Content) {
        self.header = header
        self.headerTrailing = headerTrailing
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                ZSectionHeader(header, trailing: headerTrailing)
            }
            ZCard(padding: 0, cornerRadius: ZTokens.Radius.md + ZTokens.Space.n1 / 2) {
                VStack(spacing: 0) { content }
            }
            if let footer {
                Text(footer)
                    .zType(.caption)
                    .foregroundStyle(ZTokens.Colors.screenT3)
                    .padding(.horizontal, ZTokens.Space.n2)
                    .padding(.top, ZTokens.Space.n3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("深色") {
    ZPreviewCanvas {
        ZSettingsGroup("检测", footer: "移动网络下不主动测速，节省流量。") {
            ZSettingsRow("仅在 Wi-Fi 下测速", isOn: .constant(true))
            ZDivider()
            ZSettingsRow("结果保留", accessory: .valueChevron("24 小时"))
        }
    }
}

#Preview("浅色") {
    ZPreviewCanvas(scheme: .light) {
        ZSettingsGroup("存储") {
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                Text(verbatim: "节点与规则").zType(.body)
                ZProgressBar(segments: [ZProgressSegment(id: 0, fraction: 0.27, tone: .accent),
                                        ZProgressSegment(id: 1, fraction: 0.36, tone: .neutral)], label: "存储")
                Text(verbatim: "节点 0.6 GB · 规则 1.9 GB · 可用 3.1 GB").zType(.caption).foregroundStyle(ZTokens.Colors.screenT3)
            }
            .padding(ZTokens.Space.n5)
        }
    }
}

#Preview("强调色") { ZAccentMatrix { ZSettingsGroup("外观") { ZSettingsRow("外观", accessory: .valueChevron("跟随系统")) } } }
#Preview("AX5") {
    ZPreviewCanvas(dynamicType: .accessibility5) {
        ZSettingsGroup("外观") {
            ZSettingsRow("外观", accessory: .valueChevron("跟随系统"))
            ZDivider()
            ZSettingsRow("应用图标", accessory: .valueChevron("深色"))
        }
    }
}

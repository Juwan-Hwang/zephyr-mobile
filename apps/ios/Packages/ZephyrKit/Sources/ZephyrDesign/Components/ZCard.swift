// 卡片：raised 表面 + 统一内边距。行列表卡片（首页场景、设置分组）传 padding: 0，行自带内边距，行间用 ZDivider。

import SwiftUI

public struct ZCard<Content: View>: View {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let style: ZSurfaceStyle
    private let content: Content

    public init(padding: CGFloat = ZTokens.Space.n5,
                cornerRadius: CGFloat = ZTokens.Radius.overlay,
                style: ZSurfaceStyle = .raised,
                @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.style = style
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zSurface(style, cornerRadius: cornerRadius)
            .accessibilityElement(children: .contain)
    }
}

#if DEBUG
private struct ZCardSample: View {
    var body: some View {
        ZCard {
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Nebula Cloud 已更新").zType(.body)
                    Spacer()
                    Text(verbatim: "2 小时前").zMono(.small).foregroundStyle(ZTokens.Colors.screenT3)
                }
                HStack(spacing: ZTokens.Space.n5) {
                    ZBigNumber("+1,204", size: .compact, caption: "节点", tone: ZTokens.Colors.screenGreen)
                    ZBigNumber("−318", size: .compact, caption: "节点", tone: ZTokens.Colors.screenRed)
                    ZBigNumber("0", size: .compact, caption: "规则变更")
                }
            }
            .foregroundStyle(ZTokens.Colors.screenT1)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZCardSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZCardSample() } }
#Preview("强调色") { ZAccentMatrix { ZCard { Text(verbatim: "强调").foregroundStyle(ZAccentStyle()) } } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZCardSample() } }

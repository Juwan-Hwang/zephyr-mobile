// 表面：深色玻璃（surfaceRaised + 1px borderSubtle），层次靠半透明和细边框，不靠重阴影。
// 三种：raised（卡片，默认）/ glass（材质模糊，悬浮在内容上，如底部指令栏）/ elevated（sheet、吐司、弹层）。

import SwiftUI

public enum ZSurfaceStyle: Sendable {
    /// 卡片：深色 surfaceRaised、浅色白色，1px borderSubtle。
    case raised
    /// 玻璃：系统材质模糊 + surfaceRaised 着色 + 1px borderSubtle（原型 `--glass` + blur 24）。
    case glass
    /// 浮层：surfaceElevated，1px borderDefault。
    case elevated
}

public extension View {
    /// 给任意视图套上 Zephyr 表面。`cornerRadius` 默认 `ZTokens.Radius.overlay`（原型卡片 18–22）。
    func zSurface(_ style: ZSurfaceStyle = .raised, cornerRadius: CGFloat = ZTokens.Radius.overlay) -> some View {
        modifier(ZSurfaceModifier(style: style, cornerRadius: cornerRadius))
    }
}

struct ZSurfaceModifier: ViewModifier {
    let style: ZSurfaceStyle
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background { surfaceFill(shape) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(style == .elevated ? ZTokens.Colors.borderDefault : ZTokens.Colors.borderSubtle,
                                   lineWidth: ZMetrics.hairline)
            }
    }

    @ViewBuilder
    private func surfaceFill(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .raised:
            shape.fill(ZCardFill())
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay { shape.fill(ZCardFill()) }
        case .elevated:
            shape.fill(ZTokens.Colors.surfaceElevated)
        }
    }
}

/// 容器形式：`ZSurface(.glass) { … }`。
public struct ZSurface<Content: View>: View {
    private let style: ZSurfaceStyle
    private let cornerRadius: CGFloat
    private let content: Content

    public init(_ style: ZSurfaceStyle = .raised,
                cornerRadius: CGFloat = ZTokens.Radius.overlay,
                @ViewBuilder content: () -> Content) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content.zSurface(style, cornerRadius: cornerRadius)
    }
}

#if DEBUG
private struct ZSurfaceSample: View {
    var body: some View {
        ForEach([ZSurfaceStyle.raised, .glass, .elevated], id: \.self) { style in
            ZSurface(style) {
                VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
                    Text(verbatim: "\(style)").zType(.body).foregroundStyle(ZTokens.Colors.textPrimary)
                    Text(verbatim: "深色玻璃 · 1px 细边框").zType(.footnote).foregroundStyle(ZTokens.Colors.textTertiary)
                }
                .padding(ZTokens.Space.n5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSurfaceSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSurfaceSample() } }
#Preview("强调色") { ZAccentMatrix { ZSurface { Text(verbatim: "强调").foregroundStyle(ZAccentStyle()).padding() } } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSurfaceSample() } }

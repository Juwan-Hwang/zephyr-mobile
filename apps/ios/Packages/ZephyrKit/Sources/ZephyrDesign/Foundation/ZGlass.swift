// ZGlass — 悬浮工具条（首页指令栏、资料库按钮）的玻璃底（规范 §9.7，设计评审 J-4）。
//
// iOS 26+：系统 Liquid Glass（glassEffect，交互式，不加强调色 tint，保持中性）；相邻的玻璃放进同一个
//          GlassEffectContainer，靠近时融合。
// iOS 17–25：screen.glass（0.82 不透明）叠 .ultraThinMaterial + 细描边。不提高最低系统版本。
// glassEffect 需要 iOS 26 SDK（Swift 6.2 / Xcode 26）编译；更旧的工具链只编译回退分支。
// 全 App 只有这两处用玻璃，其余卡片保持实色 screen.s1 / s2。

import SwiftUI

public extension View {
    /// 悬浮工具条玻璃底。`shape` 同时是玻璃形状、描边与命中区域。
    @ViewBuilder
    func zFloatingGlass<S: InsettableShape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            modifier(ZGlassFallback(shape: shape))
        }
        #else
        modifier(ZGlassFallback(shape: shape))
        #endif
    }
}

/// iOS 17–25 的玻璃：材质 + screen.glass + 细描边。
struct ZGlassFallback<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(ZTokens.Colors.screenGlass) }
            }
            .overlay { shape.strokeBorder(ZTokens.Colors.screenHl, lineWidth: ZMetrics.hairline) }
    }
}

/// 让相邻的悬浮玻璃在 iOS 26+ 融合（GlassEffectContainer）；更早系统原样排布。
public struct ZGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

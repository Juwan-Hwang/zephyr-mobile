// 圆形图标按钮。
// plain  = 原型 `.ibtn`（36pt，t2，按下出现底色）：首页设置、sheet 关闭
// glass  = 原型 `.lib`（52pt 玻璃圆）：首页底部资料库按钮
// accent = 导航栏 “+”（强调色图标）
// 触控区域始终 ≥ 44pt。图标随 Dynamic Type 缩放。

import SwiftUI

public enum ZIconButtonStyle: Sendable {
    case plain, glass, accent
}

public struct ZIconButton: View {
    private let systemImage: String
    private let label: LocalizedStringKey
    private let style: ZIconButtonStyle
    private let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var plainSize: CGFloat = ZMetrics.iconButton
    @ScaledMetric(relativeTo: .body) private var glassSize: CGFloat = ZMetrics.iconButtonLarge

    /// - Parameters:
    ///   - systemImage: SF Symbol 名。
    ///   - label: VoiceOver 朗读（必填，如 "资料库"、"设置"、"添加订阅"）。
    public init(systemImage: String,
                label: LocalizedStringKey,
                style: ZIconButtonStyle = .plain,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(style == .glass ? .title3 : .body)
                .fontWeight(style == .accent ? .medium : .regular)
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .modifier(ZIconButtonChrome(style: style))
                .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
                .contentShape(Circle())
        }
        .buttonStyle(ZIconPressStyle(style: style))
        .accessibilityLabel(Text(label))
    }

    private var diameter: CGFloat { style == .glass ? glassSize : plainSize }

    private var foreground: AnyShapeStyle {
        switch style {
        case .plain, .glass: return AnyShapeStyle(ZColor.t2)
        case .accent: return AnyShapeStyle(ZAccentTextStyle())
        }
    }

}

/// glass：规范 §9.7，资料库按钮与指令栏同为悬浮玻璃（iOS 26 Liquid Glass，更早回退 screen.glass + 材质）。
/// 玻璃直接加在图标上（和指令栏胶囊一样），图标画在玻璃之上。之前是 `.background { Color.clear.zFloatingGlass }`，
/// 放进 GlassEffectContainer 后，iOS 26 会把图标当成玻璃后面的内容去模糊，图标几乎看不见（J-4 第二轮录图）。
private struct ZIconButtonChrome: ViewModifier {
    let style: ZIconButtonStyle

    func body(content: Content) -> some View {
        if style == .glass {
            content.zFloatingGlass(Circle())
        } else {
            content
        }
    }
}

/// plain/accent：按下出现 `--hl` 圆底；glass：按下缩放。
private struct ZIconPressStyle: ButtonStyle {
    let style: ZIconButtonStyle

    func makeBody(configuration: Configuration) -> some View {
        ZPressStyle(haptic: .none).makeBody(configuration: configuration)
            .background {
                if style != .glass {
                    Circle()
                        .fill(ZTokens.Colors.screenS3)
                        .opacity(configuration.isPressed ? 1 : 0)
                        .animation(ZMotion.micro, value: configuration.isPressed)
                }
            }
    }
}

#if DEBUG
private struct ZIconButtonSample: View {
    var body: some View {
        HStack(spacing: ZTokens.Space.n5) {
            ZIconButton(systemImage: "sun.max", label: "设置") {}
            ZIconButton(systemImage: "xmark", label: "关闭") {}
            ZIconButton(systemImage: "plus", label: "添加订阅", style: .accent) {}
            ZIconButton(systemImage: "square.grid.2x2", label: "资料库", style: .glass) {}
        }
    }
}
#endif

#if DEBUG
#Preview("深色") { ZPreviewCanvas { ZIconButtonSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZIconButtonSample() } }
#Preview("强调色") { ZAccentMatrix { ZIconButton(systemImage: "plus", label: "添加", style: .accent) {} } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZIconButtonSample() } }
#endif

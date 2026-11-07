// 按钮（原型 `.btn`：40 高胶囊，14/500；`.ob .foot .btn` 52 高）。
// primary = 反色实心（深色白底黑字）；ghost = 细微底色；danger = 危险色字；accent = 强调色实心。
// 按下缩放 0.97 + 轻触感；大字体时高度随字号增长、文字可换行。

import SwiftUI

public enum ZButtonKind: Sendable {
    case primary, ghost, danger, accent
}

public enum ZButtonSize: Sendable {
    /// 40pt（行内确认、预览“应用/取消”）
    case regular
    /// 52pt（引导页底部主按钮、今日卡片“分享/存储图像”）
    case large
}

public struct ZButton: View {
    private let title: LocalizedStringKey
    private let kind: ZButtonKind
    private let size: ZButtonSize
    private let systemImage: String?
    private let fullWidth: Bool
    private let isLoading: Bool
    private let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var regularHeight: CGFloat = ZMetrics.buttonHeight
    @ScaledMetric(relativeTo: .body) private var largeHeight: CGFloat = ZMetrics.buttonHeightLarge

    public init(_ title: LocalizedStringKey,
                kind: ZButtonKind = .primary,
                size: ZButtonSize = .regular,
                systemImage: String? = nil,
                fullWidth: Bool = false,
                isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.size = size
        self.systemImage = systemImage
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            if !isLoading { action() }
        } label: {
            HStack(spacing: ZTokens.Space.n3) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage).imageScale(.medium)
                }
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .zType(size == .large ? .body : .button)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .large ? ZTokens.Space.n6 : ZTokens.Space.n5)
            .padding(.vertical, ZTokens.Space.n3)
            .frame(maxWidth: fullWidth ? .infinity : nil,
                   minHeight: max(size == .large ? largeHeight : regularHeight, ZTokens.Layout.touchMinIos))
            .background(Capsule(style: .continuous).fill(background))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(ZPressStyle(haptic: .none))
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text(verbatim: "处理中") : Text(verbatim: ""))
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(ZPage.background)
        case .ghost: return AnyShapeStyle(ZTokens.Colors.screenT1)
        case .danger: return AnyShapeStyle(ZTokens.Colors.screenRed)
        case .accent: return AnyShapeStyle(ZTokens.Colors.textOnAccent)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(ZTokens.Colors.screenT1)
        case .ghost, .danger: return AnyShapeStyle(ZTrackFill())
        case .accent: return AnyShapeStyle(ZAccentStyle())
        }
    }
}

#if DEBUG
private struct ZButtonSample: View {
    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ZButton("更改", fullWidth: true) {}
            ZButton("取消", kind: .ghost, fullWidth: true) {}
        }
        ZButton("应用", kind: .accent) {}
        ZButton("删除订阅", kind: .danger, systemImage: "trash") {}
        ZButton("继续", size: .large, fullWidth: true) {}
        ZButton("连接中", kind: .ghost, isLoading: true) {}
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZButtonSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZButtonSample() } }
#Preview("强调色") { ZAccentMatrix { ZButton("应用", kind: .accent) {} } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZButtonSample() } }

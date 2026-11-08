// 按钮（原型 `.btn`：40 高胶囊、14/500、左右 18；`.ob .foot .btn` 52 高、16 号）。
// primary = `.btn.p`（--t1 底 / --onp 字）；ghost = `.btn.q`（--hl 底 / --t1 字）；danger = --hl 底 / 红字；accent = `.btn.blue` 强调色实心。
// 视觉高度保持 40（regular），触控区上下各外扩 2pt 到 44（不占布局）；按下缩放 0.97，无触感；
// 大字体时高度随字号增长、文字可换行。

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
            .zType(size == .large ? .body : .zControl)
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .large ? ZTokens.Space.n6 : ZMetrics.buttonPaddingH)
            .padding(.vertical, ZTokens.Space.n3)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: visualHeight)
            .background(Capsule(style: .continuous).fill(background))
            // 视觉 40 → 触控 44：外扩的透明区只参与命中，下面的负 padding 把它从布局里去掉。
            .padding(.vertical, hitOutset)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZPressStyle(haptic: .none))
        .padding(.vertical, -hitOutset)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text(verbatim: "处理中") : Text(verbatim: ""))
    }

    private var visualHeight: CGFloat { size == .large ? largeHeight : regularHeight }

    /// 视觉高度不足 44 时，上下各需外扩的触控量（AX 尺寸下按钮本身已 ≥ 44，为 0）。
    private var hitOutset: CGFloat { max(0, (ZTokens.Layout.touchMinIos - visualHeight) / 2) }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(ZTokens.Colors.screenOnPrimary)
        case .ghost: return AnyShapeStyle(ZTokens.Colors.screenT1)
        case .danger: return AnyShapeStyle(ZTokens.Colors.screenRed)
        case .accent: return AnyShapeStyle(ZTokens.Colors.textOnAccent)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(ZTokens.Colors.screenT1)
        case .ghost, .danger: return AnyShapeStyle(ZTokens.Colors.screenHl)
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

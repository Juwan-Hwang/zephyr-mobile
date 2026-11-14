// 连接状态点（原型 `.wm i`）：关 = 20% 灰；开 = 绿色 + 4pt 浅绿外环。颜色变化 400ms 内淡入。
// 「辅助功能 › 不以颜色区分」（X-P1-10）：关 = 空心环；开 = 实心圆；覆盖色（警示态）= 实心菱形——三态靠形状即可分辨。

import SwiftUI

public struct ZStatusDot: View {
    private let isOn: Bool
    private let color: Color?

    /// - Parameter color: 覆盖“开”的颜色（默认开关绿）；例如服务不可用时传 `ZTokens.Colors.screenAmber`。
    public init(isOn: Bool, color: Color? = nil) {
        self.isOn = isOn
        self.color = color
    }

    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColorOnly
    @Environment(\.zStaticRendering) private var still

    public var body: some View {
        let on = color ?? ZSwitchColor.on
        Group {
            if noColorOnly {
                shapeCoded(on: on)
            } else {
                Circle()
                    .fill(isOn ? AnyShapeStyle(on) : AnyShapeStyle(ZQuaternaryText()))
            }
        }
        .frame(width: ZMetrics.statusDot, height: ZMetrics.statusDot)
        .background {
            Circle()
                .fill(on.opacity(isOn ? 0.14 : 0))
                .padding(-ZMetrics.statusRing)
        }
        .animation(still ? nil : ZMotion.standard, value: isOn)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func shapeCoded(on: Color) -> some View {
        if !isOn {
            Circle().strokeBorder(ZQuaternaryText(), lineWidth: 1.5)
        } else if color != nil {
            Rectangle().fill(on).rotationEffect(.degrees(45)).scaleEffect(0.78)
        } else {
            Circle().fill(on)
        }
    }
}

#Preview("深色") {
    ZPreviewCanvas {
        HStack(spacing: ZTokens.Space.n6) {
            ZStatusDot(isOn: false)
            ZStatusDot(isOn: true)
            ZStatusDot(isOn: true, color: ZTokens.Colors.screenAmber)
        }
    }
}

#Preview("浅色") {
    ZPreviewCanvas(scheme: .light) {
        HStack(spacing: ZTokens.Space.n6) {
            ZStatusDot(isOn: false)
            ZStatusDot(isOn: true)
        }
    }
}

// 连接状态点（原型 `.wm i`）：关 = 20% 灰；开 = 绿色 + 4pt 浅绿外环。颜色变化 400ms 内淡入。

import SwiftUI

public struct ZStatusDot: View {
    private let isOn: Bool
    private let color: Color?

    /// - Parameter color: 覆盖“开”的颜色（默认开关绿）；例如服务不可用时传 `ZTokens.Colors.colorWarning`。
    public init(isOn: Bool, color: Color? = nil) {
        self.isOn = isOn
        self.color = color
    }

    public var body: some View {
        let on = color ?? ZSwitchColor.on
        Circle()
            .fill(isOn ? AnyShapeStyle(on) : AnyShapeStyle(ZQuaternaryText()))
            .frame(width: ZMetrics.statusDot, height: ZMetrics.statusDot)
            .background {
                Circle()
                    .fill(on.opacity(isOn ? 0.14 : 0))
                    .padding(-ZMetrics.statusRing)
            }
            .animation(ZMotion.standard, value: isOn)
            .accessibilityHidden(true)
    }
}

#Preview("深色") {
    ZPreviewCanvas {
        HStack(spacing: ZTokens.Space.n6) {
            ZStatusDot(isOn: false)
            ZStatusDot(isOn: true)
            ZStatusDot(isOn: true, color: ZTokens.Colors.colorWarning)
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

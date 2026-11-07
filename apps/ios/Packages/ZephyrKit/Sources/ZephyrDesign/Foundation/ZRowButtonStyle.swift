// 列表行的按下态（原型 `.row:active{background:rgba(255,255,255,.025)}`）：不缩放，底色微亮 + 轻触感。
// 用于 ZGroupCard / ZNodeRow / ZProfileCard / ZSettingsRow 等整行可点的场景。

import SwiftUI

public struct ZRowButtonStyle: ButtonStyle {
    public var haptic: ZHaptic

    public init(haptic: ZHaptic = .none) {
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? ZTokens.Colors.screenPressed : Color.clear)
            .animation(ZMotion.micro, value: configuration.isPressed)
            .modifier(ZHapticOnPress(isPressed: configuration.isPressed, haptic: haptic))
    }
}

// 按下缩放 + 触感。所有可点 Z* 组件共用。
// 缩放比例 ZTokens.Motion.pressScale（0.97），时长 ZTokens.Time.micro；Reduce Motion 下不缩放、只降低透明度。

import SwiftUI

/// 触感强度。
public enum ZHaptic: Sendable {
    case none, selection, light, medium, rigid

    var feedback: SensoryFeedback? {
        switch self {
        case .none: return nil
        case .selection: return .selection
        case .light: return .impact(weight: .light)
        case .medium: return .impact(weight: .medium)
        case .rigid: return .impact(flexibility: .rigid)
        }
    }
}

/// `Button { } label: { }.buttonStyle(ZPressStyle())`
public struct ZPressStyle: ButtonStyle {
    public var scale: CGFloat
    public var haptic: ZHaptic

    public init(scale: CGFloat = CGFloat(ZTokens.Motion.pressScale), haptic: ZHaptic = .none) {
        self.scale = scale
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        ZPressBody(configuration: configuration, scale: scale, haptic: haptic)
    }
}

private struct ZPressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let haptic: ZHaptic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed && reduceMotion ? 0.7 : (isEnabled ? 1 : 0.4))
            .animation(ZMotion.micro, value: pressed)
            .contentShape(Rectangle())
            .modifier(ZHapticOnPress(isPressed: pressed, haptic: haptic))
    }
}

/// 按下瞬间触发一次触感（松开不触发）。
struct ZHapticOnPress: ViewModifier {
    let isPressed: Bool
    let haptic: ZHaptic

    func body(content: Content) -> some View {
        if let feedback = haptic.feedback {
            content.sensoryFeedback(feedback, trigger: isPressed) { _, new in new }
        } else {
            content
        }
    }
}

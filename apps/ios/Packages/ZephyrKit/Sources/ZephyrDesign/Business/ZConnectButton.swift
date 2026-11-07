// 首页右上的大号连接开关（原型 `.sw`：66×40 胶囊，白色旋钮 34，开 = 绿色；按下旋钮加宽到 40）。
// 状态切换：旋钮 spring（ZTokens.Motion.spring），开启时外发光（glowRadius 28 / glowAlpha 0.35）。
// 连接中/断开中：旋钮里转圈。Reduce Motion：无光晕、无弹簧（200ms 缓动）。
// 触感：按下 medium；连上 success。VoiceOver：开关语义（.isToggle），值为 已连接 / 未连接 / 正在连接…

import SwiftUI

public enum ZConnectPhase: Sendable, Equatable {
    case off, connecting, on, disconnecting

    var isOnSide: Bool { self == .on || self == .connecting }
    var isBusy: Bool { self == .connecting || self == .disconnecting }
}

public enum ZConnectTint: Sendable {
    /// 原型：系统绿
    case success
    /// 跟随 `.zAccent`
    case accent
}

public struct ZConnectButton: View {
    private let phase: ZConnectPhase
    private let tint: ZConnectTint
    private let action: () -> Void

    public init(phase: ZConnectPhase, tint: ZConnectTint = .success, action: @escaping () -> Void) {
        self.phase = phase
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(ZConnectSwitchStyle(phase: phase, tint: tint))
            .sensoryFeedback(.success, trigger: phase) { _, new in new == .on }
            .accessibilityLabel(Text(verbatim: "连接"))
            .accessibilityValue(Text(verbatim: spokenValue))
            .accessibilityAddTraits(.isToggle)
            .accessibilityHint(Text(verbatim: phase.isOnSide ? "轻点两下断开" : "轻点两下连接"))
    }

    private var spokenValue: String {
        switch phase {
        case .off: return "未连接"
        case .connecting: return "正在连接"
        case .on: return "已连接"
        case .disconnecting: return "正在断开"
        }
    }
}

private struct ZConnectSwitchStyle: ButtonStyle {
    let phase: ZConnectPhase
    let tint: ZConnectTint

    func makeBody(configuration: Configuration) -> some View {
        ZConnectSwitch(phase: phase, tint: tint, isPressed: configuration.isPressed)
    }
}

private struct ZConnectSwitch: View {
    let phase: ZConnectPhase
    let tint: ZConnectTint
    let isPressed: Bool
    @Environment(\.zAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var scaledWidth: CGFloat = ZMetrics.connectWidth

    var body: some View {
        // 大字体时适度放大（最多 1.25 倍），保持 66:40 比例。
        let k = min(max(scaledWidth / ZMetrics.connectWidth, 1), 1.25)
        let width = ZMetrics.connectWidth * k
        let height = ZMetrics.connectHeight * k
        let inset = ZMetrics.connectInset * k
        let knobH = ZMetrics.connectKnob * k
        let knobW = (isPressed ? ZMetrics.connectKnobPressed : ZMetrics.connectKnob) * k
        let travel = width - inset * 2 - knobW
        let onColor = tint == .success ? ZSwitchColor.on : accent.color
        let lit = phase == .on
        let glowing = lit && !reduceMotion

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(phase.isOnSide ? onColor : ZSwitchColor.off)
                .opacity(phase.isBusy ? 0.6 : 1)
            Capsule(style: .continuous)
                .fill(Color.white)
                .frame(width: knobW, height: knobH)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                .overlay {
                    if phase.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(onColor)
                    }
                }
                .offset(x: inset + (phase.isOnSide ? travel : 0))
        }
        .frame(width: width, height: height)
        .shadow(color: onColor.opacity(glowing ? ZTokens.Motion.glowAlpha : 0),
                radius: glowing ? ZTokens.Motion.glowRadius : 0)
        .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
        .contentShape(Capsule(style: .continuous))
        .animation(ZMotion.gentle(ZMotion.spring, reduceMotion: reduceMotion), value: phase)
        .animation(ZMotion.micro, value: isPressed)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed) { _, new in new }
    }
}

#if DEBUG
private struct ZConnectSample: View {
    @State var phase: ZConnectPhase = .on
    var body: some View {
        HStack(alignment: .bottom) {
            Text(verbatim: phase == .on ? "已连接" : "未连接")
                .zDisplay(.title, weight: .light)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Spacer()
            ZConnectButton(phase: phase) {
                phase = phase == .on ? .off : .on
            }
        }
        HStack(spacing: ZTokens.Space.n5) {
            ZConnectButton(phase: .off) {}
            ZConnectButton(phase: .connecting) {}
            ZConnectButton(phase: .disconnecting) {}
            ZConnectButton(phase: .on, tint: .accent) {}
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZConnectSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZConnectSample() } }
#Preview("强调色") { ZAccentMatrix { ZConnectButton(phase: .on, tint: .accent) {} } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZConnectSample() } }

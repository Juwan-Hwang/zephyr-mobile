// 首页连接开关（原型 `.sw`：66×40 胶囊，旋钮 34，按下旋钮加宽到 40，开 = 系统绿）。
// 待替换：D 的 ZConnectButton 落地后换掉（见 NOTES-H.md）。
// 连接中：轨道绿色脉动；Reduce Motion 下不脉动、旋钮无弹簧。VoiceOver 作为开关朗读。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct HConnectSwitch: View {
    let status: ConnectionStatus
    let action: () -> Void

    @GestureState private var pressed = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    private var isOn: Bool { status == .connected || status == .connecting }
    private var busy: Bool { status == .connecting || status == .disconnecting }

    var body: some View {
        let s = min(scale, 1.4)
        let w = HMetrics.switchWidth * s, h = HMetrics.switchHeight * s
        let inset = HMetrics.switchInset * s
        let knobW = (pressed ? HMetrics.switchKnobPressed : HMetrics.switchKnob) * s
        let knobH = HMetrics.switchKnob * s

        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? AnyShapeStyle(ZSwitchColor.on) : AnyShapeStyle(ZSwitchColor.off))
                .opacity(busy && pulse ? 0.6 : 1)
            Capsule(style: .continuous)
                .fill(.white)
                .frame(width: knobW, height: knobH)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                .padding(inset)
        }
        .frame(width: w, height: h)
        .contentShape(Capsule())
        .animation(reduceMotion ? ZMotion.standard : ZMotion.spring, value: isOn)
        .animation(ZMotion.micro, value: pressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, st, _ in st = true }
                .onEnded { _ in action() }
        )
        .sensoryFeedback(.impact(weight: isOn ? .medium : .light), trigger: isOn)
        .onChange(of: busy, initial: true) { _, b in
            guard !reduceMotion else { pulse = false; return }
            if b {
                withAnimation(ZMotion.slow.repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(ZMotion.standard) { pulse = false }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "连接"))
        .accessibilityValue(Text(verbatim: isOn ? "开" : "关"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityHint(Text(verbatim: busy ? "正在处理" : (isOn ? "轻点两下断开" : "轻点两下连接")))
    }
}

#Preview {
    VStack(spacing: ZTokens.Space.n6) {
        HConnectSwitch(status: .disconnected) {}
        HConnectSwitch(status: .connecting) {}
        HConnectSwitch(status: .connected) {}
    }
    .padding()
    .zPageBackground()
}

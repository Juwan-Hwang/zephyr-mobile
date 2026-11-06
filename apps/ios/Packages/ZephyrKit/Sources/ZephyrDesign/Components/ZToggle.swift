// 开关：系统 Toggle（原生无障碍、触感、尺寸 51×31），按原型着绿色（`.tog.on{background:var(--green)}`），
// 可选强调色。切换时额外给一次 selection 触感。

import SwiftUI

public enum ZToggleTint: Sendable {
    /// 原型默认：系统绿（latencyGood）
    case success
    /// 跟随 `.zAccent`
    case accent
}

public struct ZToggle<Label: View>: View {
    @Binding private var isOn: Bool
    private let tint: ZToggleTint
    private let label: Label
    @Environment(\.zAccent) private var accent

    public init(isOn: Binding<Bool>, tint: ZToggleTint = .success, @ViewBuilder label: () -> Label) {
        _isOn = isOn
        self.tint = tint
        self.label = label()
    }

    public var body: some View {
        Toggle(isOn: $isOn) { label }
            .tint(tint == .success ? ZSwitchColor.on : accent.color)
            .sensoryFeedback(.selection, trigger: isOn)
    }
}

public extension ZToggle where Label == Text {
    /// 带标题的开关。只显示开关时加 `.labelsHidden()`（标题仍用于 VoiceOver）。
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, tint: ZToggleTint = .success) {
        self.init(isOn: isOn, tint: tint) { Text(title) }
    }
}

#if DEBUG
private struct ZToggleSample: View {
    @State private var a = true
    @State private var b = false
    var body: some View {
        ZToggle("按需连接", isOn: $a).zType(.body)
        ZToggle("更新前显示更改", isOn: $b).zType(.body)
        ZToggle("强调色开关", isOn: $a, tint: .accent).zType(.body)
        ZToggle("仅开关", isOn: $b).labelsHidden()
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZToggleSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZToggleSample() } }
#Preview("强调色") { ZAccentMatrix { ZToggle("强调色", isOn: .constant(true), tint: .accent) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZToggleSample() } }

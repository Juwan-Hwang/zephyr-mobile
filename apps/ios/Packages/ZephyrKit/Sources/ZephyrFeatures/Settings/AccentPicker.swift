// AccentPicker — 强调色 4 选 1（蓝 / 绿 / 橙 / 粉，ZTokens.Accent）。圆点 + 选中外环；VoiceOver 按单选读。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct AccentPicker: View {
    @Binding var selection: Accent
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = ZTokens.Space.n6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ForEach(Accent.allCases, id: \.self) { a in
                let on = a == selection
                Button {
                    withAnimation(ZMotion.motion(ZMotion.micro, reduceMotion: reduceMotion)) { selection = a }
                } label: {
                    Circle()
                        .fill(Self.color(a))
                        .frame(width: dot, height: dot)
                        .padding(ZTokens.Space.n1 / 2)
                        .overlay {
                            Circle().strokeBorder(on ? Self.color(a) : .clear, lineWidth: ZTokens.Space.n1 / 2)
                                .padding(-ZTokens.Space.n1 / 2)
                        }
                        .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .selection))
                .accessibilityLabel(Text(verbatim: Self.title(a)))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func color(_ a: Accent) -> Color {
        (ZTokens.Accent(rawValue: a.rawValue) ?? .blue).color
    }

    static func title(_ a: Accent) -> String {
        switch a {
        case .blue: ZL.tr("蓝色")
        case .green: ZL.tr("绿色")
        case .orange: ZL.tr("橙色")
        case .pink: ZL.tr("粉色")
        }
    }
}

#Preview {
    @Previewable @State var a: Accent = .blue
    ZSettingsGroup("外观") {
        ZSettingsRow("强调色") { AccentPicker(selection: $a) }
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}

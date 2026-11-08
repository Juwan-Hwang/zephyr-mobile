// OnboardingChoiceCard — 引导第 2 步的单选卡（原型 .opt）：左侧单选圆 + 标题 + 说明；
// 选中：强调色描边 + 7% 强调色底，圆变为强调色粗环。

import SwiftUI
import ZephyrDesign

struct OnboardingChoiceCard: View {
    var title: LocalizedStringKey
    var detail: LocalizedStringKey
    var isOn: Bool
    var action: () -> Void
    @ScaledMetric(relativeTo: .body) private var radio: CGFloat = ZTokens.Space.n6 - ZTokens.Space.n1 / 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat { ZTokens.Radius.overlay - ZTokens.Space.n1 / 2 }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: ZTokens.Space.n4) {
                Circle()
                    .strokeBorder(isOn ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(ZQuaternaryText()),
                                  lineWidth: isOn ? radio * 0.32 : ZTokens.Space.n1 / 2)
                    .frame(width: radio, height: radio)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                    Text(title)
                        .zType(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                    Text(detail)
                        .zType(.footnote)
                        .foregroundStyle(ZColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(ZTokens.Space.n5 + ZTokens.Space.n1 / 2)
            .zSurface(.raised, cornerRadius: radius)
            .background(isOn ? AnyShapeStyle(ZAccentStyle(opacity: 0.07)) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isOn ? AnyShapeStyle(ZAccentStyle()) : AnyShapeStyle(Color.clear), lineWidth: 1)
            }
            .animation(ZMotion.motion(ZMotion.standard, reduceMotion: reduceMotion), value: isOn)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(ZPressStyle(haptic: .selection))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview {
    VStack(spacing: ZTokens.Space.n4) {
        OnboardingChoiceCard(title: "简单", detail: "使用订阅提供的分组。节点不可用时自动处理。", isOn: false) {}
        OnboardingChoiceCard(title: "优选", detail: "每天在 Wi‑Fi 下检测节点。AI 与视频仅使用检测通过的节点。每次约 3 MB。", isOn: true) {}
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}

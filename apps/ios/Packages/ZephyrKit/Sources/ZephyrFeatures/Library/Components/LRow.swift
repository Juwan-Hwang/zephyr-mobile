// LRow — 分组卡片里的一行（原型 .gr）：标题 / 副标题 / 右侧值 / ›。
// 传 action 时整行是按钮（最小 44pt 触控、按下高亮、VoiceOver 读作按钮）。

import SwiftUI
import ZephyrDesign

struct LRow<Accessory: View>: View {
    var title: String
    var subtitle: String?
    var value: String?
    var showsChevron: Bool
    var action: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, subtitle: String? = nil, value: String? = nil, showsChevron: Bool = false,
         action: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title; self.subtitle = subtitle; self.value = value
        self.showsChevron = showsChevron; self.action = action; self.accessory = accessory
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(LRowButtonStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: ZTokens.Space.n4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .zType(.caption)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                }
                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ZTokens.Colors.textTertiary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, ZTokens.Space.n4 + 2)
        .padding(.vertical, ZTokens.Space.n4)
        .frame(minHeight: LStyle.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension LRow where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil, value: String? = nil, showsChevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, value: value, showsChevron: showsChevron, action: action, accessory: { EmptyView() })
    }
}

/// 行按下高亮。
struct LRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ZTokens.Colors.bgMuted : .clear)
            .animation(.easeOut(duration: ZTokens.Time.micro), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 0) {
        LRow("受信任的 Wi‑Fi", subtitle: "连接后自动断开", value: "家", showsChevron: true, action: {})
        LDivider()
        LRow("结果保留", value: "24 小时", showsChevron: true, action: {})
    }
    .lCard()
    .padding()
    .background(LStyle.pageBackground)
}

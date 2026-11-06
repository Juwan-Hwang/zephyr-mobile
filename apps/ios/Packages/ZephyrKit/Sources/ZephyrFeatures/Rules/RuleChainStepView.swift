// RuleChainStepView — 命中链的一步（原型 .chain .st）：左侧圆点 + 竖线，小标签 + 值，右侧注释。
// 最后一步圆点实心强调色。

import SwiftUI
import ZephyrDesign

struct RuleChainStepView: View {
    var step: RulesModel.Step
    var isLast: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: ZTokens.Space.n4) {
            dot.frame(width: 9, height: 9)   // 原型 .st i 9px
            VStack(alignment: .leading, spacing: 1) {
                Text(step.label)
                    .zType(.caption)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                value
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = step.trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .monospaced()
                    .foregroundStyle(ZTokens.Colors.textTertiary)
            }
        }
        .padding(.vertical, ZTokens.Space.n2)
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(ZTokens.Colors.borderDefault)
                    .frame(width: 1)
                    .padding(.leading, 4)
                    .padding(.top, ZTokens.Space.n6 - 2)
                    .padding(.bottom, -ZTokens.Space.n3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var dot: some View {
        if isLast {
            Circle().fill(.tint)
        } else {
            Circle()
                .fill(LStyle.cardFill(scheme))
                .overlay(Circle().strokeBorder(ZTokens.Colors.textTertiary, lineWidth: 1.5))
        }
    }

    @ViewBuilder private var value: some View {
        switch step.value {
        case .text(let s):
            Text(s).zType(.body)
        case .mono(let s):
            Text(s).font(.subheadline).monospaced()
        case .region(let code, let name):
            HStack(spacing: ZTokens.Space.n2) {
                Text(code)
                    .font(.caption.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(ZTokens.Colors.textSecondary)
                    .padding(.horizontal, ZTokens.Space.n2)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ZTokens.Colors.borderDefault))
                Text(name).zType(.body)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        RuleChainStepView(step: .init(id: 0, label: "请求", value: .mono("chat.openai.com")), isLast: false)
        RuleChainStepView(step: .init(id: 1, label: "第 3 层 · OpenAI", value: .mono("DOMAIN-SUFFIX,openai.com"), trailing: "#41"), isLast: false)
        RuleChainStepView(step: .init(id: 2, label: "场景 · AI", value: .region(code: "SG", name: "新加坡 02")), isLast: false)
        RuleChainStepView(step: .init(id: 3, label: "出口 IP", value: .mono("198.51.100.7")), isLast: true)
    }
    .padding()
    .lCard()
    .padding()
    .background(LStyle.pageBackground)
}

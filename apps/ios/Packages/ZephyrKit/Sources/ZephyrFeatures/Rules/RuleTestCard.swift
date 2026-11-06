// RuleTestCard — 规则测试卡（原型 .rt）：顶部等宽输入框，下方命中链与用时；空输入时给提示。

import SwiftUI
import ZephyrDesign

struct RuleTestCard: View {
    @Binding var input: String
    var steps: [RulesModel.Step]
    var took: String?
    var invalid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LSearchField(prompt: "测试域名或 IP", text: $input, monospaced: true, filled: false, submitLabel: .done)
            LDivider()
            VStack(alignment: .leading, spacing: 0) {
                if input.trimmingCharacters(in: .whitespaces).isEmpty {
                    hint("输入域名或 IP，查看匹配的规则与出口。")
                } else if invalid {
                    hint("无法识别的域名或 IP。")
                } else {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        RuleChainStepView(step: step, isLast: i == steps.count - 1)
                            .transition(.opacity)
                    }
                    if let took {
                        Text(took)
                            .font(.caption.monospacedDigit())
                            .monospaced()
                            .foregroundStyle(ZTokens.Colors.textTertiary)
                            .padding(.top, ZTokens.Space.n3)
                            .padding(.leading, ZTokens.Space.n6 - 3)
                    }
                }
            }
            .padding(.horizontal, ZTokens.Space.n5)
            .padding(.top, ZTokens.Space.n4 + 2)
            .padding(.bottom, ZTokens.Space.n5)
            .animation(.easeOut(duration: ZTokens.Time.micro), value: steps)
        }
        .lCard(radius: ZTokens.Radius.md + 2)
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .zType(.footnote)
            .foregroundStyle(ZTokens.Colors.textTertiary)
            .padding(.vertical, ZTokens.Space.n1)
    }
}

#Preview {
    @Previewable @State var q = "ads.doubleclick.net"
    RuleTestCard(input: $q, steps: [
        .init(id: 0, label: "请求", value: .mono(q)),
        .init(id: 1, label: "第 4 层 · 广告与跟踪", value: .mono("DOMAIN-KEYWORD,ads"), trailing: "#18,204,451"),
        .init(id: 2, label: "结果", value: .text("已拦截")),
    ], took: "用时 0.12 ms", invalid: false)
    .padding()
    .background(LStyle.pageBackground)
}

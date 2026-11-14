// RuleTestCard — 规则测试卡（原型 .rt）：顶部等宽输入框（ZTextField .plain），下方命中链（ZChainStep）与用时；
// 空输入 / 无法识别时给提示。

import SwiftUI
import ZephyrDesign

struct RuleTestCard: View {
    @Binding var input: String
    var steps: [RulesModel.Step]
    var took: String?
    var invalid: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zStaticRendering) private var still

    var body: some View {
        ZCard(padding: 0, cornerRadius: ZTokens.Radius.md + ZTokens.Space.n1 / 2) {
            VStack(alignment: .leading, spacing: 0) {
                ZTextField("测试域名或 IP", text: $input, style: .plain, monospaced: true)
                ZDivider()
                VStack(alignment: .leading, spacing: 0) {
                    if input.trimmingCharacters(in: .whitespaces).isEmpty {
                        hint("输入域名或 IP，查看匹配的规则与出口。")
                    } else if invalid {
                        hint("无法识别的域名或 IP。")
                    } else {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                            chainStep(step, position: .at(i, of: steps.count))
                                .transition(.opacity)
                        }
                        if let took {
                            Text(verbatim: took)
                                .zMono(.small)
                                .foregroundStyle(ZColor.t3)
                                .padding(.top, ZTokens.Space.n3)
                        }
                    }
                }
                .padding(.horizontal, ZTokens.Space.n5)
                .padding(.top, ZTokens.Space.n4)
                .padding(.bottom, ZTokens.Space.n5)
                .animation(ZMotion.motion(ZMotion.micro, reduceMotion: reduceMotion || still), value: steps)
            }
        }
    }

    private func chainStep(_ step: RulesModel.Step, position: ZChainPosition) -> ZChainStep {
        switch step.value {
        case .text(let s):
            ZChainStep(label: step.label, value: s, trailing: step.trailing, position: position)
        case .mono(let s):
            ZChainStep(label: step.label, value: s, trailing: step.trailing, monospacedValue: true, position: position)
        case .region(let code, let name):
            ZChainStep(label: step.label, value: name, trailing: step.trailing, regionCode: code, position: position)
        }
    }

    private func hint(_ s: String) -> some View {
        Text(verbatim: s)
            .zType(.footnote)
            .foregroundStyle(ZColor.t3)
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
    .zPageBackground()
    .preferredColorScheme(.dark)
}

// RuleAddSheet — 右上角“+”：添加覆写规则。
// 契约 v0 还没有写覆写规则的接口，这里先给出完整的输入界面，“添加”禁用并说明去处（见 NOTES-L 缺口）。

import SwiftUI
import ZephyrDesign

struct RuleAddSheet: View {
    @State private var target = ""
    @State private var policy = "直连"
    @Environment(\.dismiss) private var dismiss
    private let policies = ["直连", "AI", "视频", "其他", "拦截"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ZTextField("域名、关键词或 IP 段", text: $target, systemImage: nil, monospaced: true)
                    .padding(.top, ZTokens.Space.n5)
                ZSectionHeader("使用")
                ZSegmented(policies.map { ZSegment($0, verbatim: $0) }, selection: $policy, label: "使用")
                Text(verbatim: "覆写位于第 1 层，在订阅规则之上，订阅更新时保持不变。此版本暂不支持在手机上保存覆写，可在电脑上的 Zephyr 中添加，同步后生效。")
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ZTokens.Space.n2)
                    .padding(.top, ZTokens.Space.n4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PageMetrics.margin)
            .zPageBackground()
            .navigationTitle(Text(verbatim: "添加覆写"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: "取消") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {} label: { Text(verbatim: "添加") }.disabled(true)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    RuleAddSheet()
        .preferredColorScheme(.dark)
}

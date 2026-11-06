// RuleAddSheet — 右上角“+”：添加覆写规则。
// 契约 v0 还没有写覆写规则的接口，这里先给出完整的输入界面，提交按钮禁用并说明去处（见 NOTES-L 缺口）。

import SwiftUI
import ZephyrDesign

struct RuleAddSheet: View {
    @State private var target = ""
    @State private var policy = 0
    @Environment(\.dismiss) private var dismiss
    private let policies = ["直连", "AI", "视频", "其他", "拦截"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                LSearchField(prompt: "域名、关键词或 IP 段", text: $target, monospaced: true, submitLabel: .done)
                    .padding(.horizontal, LStyle.margin)
                    .padding(.top, ZTokens.Space.n5)
                LSectionHeader("使用")
                Picker("使用", selection: $policy) {
                    ForEach(policies.indices, id: \.self) { Text(policies[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LStyle.margin)
                Text("覆写位于第 1 层，在订阅规则之上，订阅更新时保持不变。此版本暂不支持在手机上保存覆写，可在电脑上的 Zephyr 中添加，同步后生效。")
                    .lFootnoteStyle()
                Spacer()
            }
            .background(LStyle.pageBackground)
            .navigationTitle("添加覆写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("添加") {}.disabled(true) }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    RuleAddSheet()
}

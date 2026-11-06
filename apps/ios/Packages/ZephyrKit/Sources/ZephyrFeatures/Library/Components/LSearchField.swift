// LSearchField — 搜索/测试输入框（原型 .fs）：放大镜 + 输入 + 右侧信息（“220,412 个 · 0.70 ms”）+ 清除。
// filled = true 为节点页的灰底圆角框；false 为嵌入规则卡片顶部的无底样式（等宽字体）。

import SwiftUI
import ZephyrDesign

struct LSearchField: View {
    var prompt: String
    @Binding var text: String
    var info: String?
    var monospaced = false
    var filled = true
    var submitLabel: SubmitLabel = .search
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(monospaced ? .URL : .default)
                .submitLabel(submitLabel)
                .focused($focused)
            if let info, !text.isEmpty {
                Text(info)
                    .font(.caption.monospacedDigit())
                    .monospaced()
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .accessibilityLabel(info)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                        .frame(minWidth: ZTokens.Layout.touchMinIos * 0.6, minHeight: ZTokens.Layout.touchMinIos * 0.6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, ZTokens.Space.n4)
        .frame(minHeight: filled ? ZTokens.Space.n7 + ZTokens.Space.n3 : ZTokens.Space.n8)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: ZTokens.Radius.surface, style: .continuous)
                    .fill(ZTokens.Colors.bgMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

#Preview {
    @Previewable @State var q = "东京 IPLC"
    VStack {
        LSearchField(prompt: "地区、城市或线路", text: $q, info: "220,412 个 · 0.70 ms")
        LSearchField(prompt: "测试域名或 IP", text: .constant("chat.openai.com"), monospaced: true, filled: false)
    }
    .padding()
    .background(LStyle.pageBackground)
}

// 指令层（原型 07，截图 cmd.png）：底部搜索栏展开为全屏玻璃层。
//   [🔍 Gemini 走日本            取消]   ← 识别出的词带下划线（服务蓝 / 地区绿 / 操作黄）
//   指令  [服务 Gemini] [地区 日本] [范围 AI]
//   预览卡：Gemini 使用日本节点 / 3 个可用，将使用东京 03。/ 出口 IP 将更改 SG … → JP … / [应用]
//   其余建议（引擎 commandSuggestions，≤ 8 条）
// 空输入时显示"建议"。回车 = 应用主预览（没有则执行第一条建议）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct CommandView: View {
    let prefill: String
    @Environment(AppModel.self) private var app
    @State private var model: CommandModel?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(ZPage.background.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            if let model {
                VStack(spacing: 0) {
                    CommandField(model: model, focused: $focused, onSubmit: submit, onCancel: close)
                        .offset(y: appeared || reduceMotion ? 0 : ZTokens.Space.n4)
                    ScrollView {
                        CommandResults(model: model, onRun: run, onApply: apply)
                            .padding(.bottom, ZTokens.Space.n8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                }
                .padding(.top, ZTokens.Space.n3)
            }
        }
        .onAppear {
            let m = CommandModel(app: app)
            m.start(prefill: prefill)
            model = m
            withAnimation(ZMotion.slow) { appeared = true }
            focused = true
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private func close() {
        focused = false
        app.closeCommand()
    }

    private func submit() {
        guard let model else { return }
        if model.preview?.node != nil { apply() }
        else if let first = model.suggestions.first { run(first) }
    }

    private func apply() {
        guard let model else { return }
        Task {
            if await model.applyPreview() { HHaptics.confirm(); close() }
        }
    }

    private func run(_ s: CommandSuggestion) {
        guard let model else { return }
        Task {
            await model.run(s)
            if s.kind != .openNodeQuery && s.kind != .testRule && s.kind != .openPage { HHaptics.confirm() }
            if app.isCommandPresented { close() }
        }
    }
}

/// 输入框：透明 TextField 叠一层带下划线的镜像文字（原型 `.fld .mir`），光标用强调色。
private struct CommandField: View {
    @Bindable var model: CommandModel
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ScaledMetric(relativeTo: .body) private var height = HMetrics.commandFieldHeight

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                mirror
                    .lineLimit(1)
                    .accessibilityHidden(true)
                TextField(text: $model.input, prompt: Text(verbatim: "搜索或输入指令").foregroundStyle(ZTokens.Colors.textTertiary)) {
                    Text(verbatim: "指令")
                }
                .foregroundStyle(model.input.isEmpty ? AnyShapeStyle(ZTokens.Colors.textPrimary) : AnyShapeStyle(Color.clear))
                .tint(ZAccentStyle())
                .focused(focused)
                .submitLabel(.go)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            .zType(.headline).fontWeight(.regular)
            Button(action: onCancel) {
                Text(verbatim: "取消").zType(.body).foregroundStyle(ZAccentStyle())
                    .frame(minHeight: ZTokens.Layout.touchMinIos)
            }
            .buttonStyle(ZPressStyle(haptic: .light))
        }
        .padding(.horizontal, ZTokens.Space.n5)
        .frame(minHeight: height)
        .zSurface(.elevated, cornerRadius: height / 2)
        .padding(.horizontal, HMetrics.cardInset)
    }

    /// 镜像文字：识别出的片段加 2pt 下划线（服务 = 强调色、地区 = 成功色、操作 = 警告色）。
    private var mirror: Text {
        let chars = Array(model.input)
        guard !chars.isEmpty else { return Text(verbatim: "") }
        let marks = model.parse.tokens.compactMap { t in t.range.map { ($0, t.kind) } }.sorted { $0.0.lowerBound < $1.0.lowerBound }
        var out = Text(verbatim: "")
        var i = 0
        for (r, kind) in marks where r.lowerBound >= i && r.upperBound <= chars.count {
            out = out + Text(verbatim: String(chars[i..<r.lowerBound]))
            out = out + Text(verbatim: String(chars[r])).underline(true, color: color(kind))
            i = r.upperBound
        }
        out = out + Text(verbatim: String(chars[i...]))
        return out.foregroundColor(ZTokens.Colors.textPrimary)
    }

    private func color(_ k: CommandToken.Kind) -> Color {
        switch k {
        case .service, .scene: ZTokens.Colors.colorDownload
        case .region: ZTokens.Colors.colorSuccess
        case .action: ZTokens.Colors.colorWarning
        case .scope: ZTokens.Colors.textTertiary
        }
    }
}

#Preview("指令 · Gemini 走日本") {
    HPreview(model: .preview()) { CommandView(prefill: "Gemini 走日本") }
}

#Preview("指令 · 空") {
    HPreview(model: .preview()) { CommandView(prefill: "") }
}

// 指令结果区：token 卡片、主预览卡、建议列表、无结果。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct CommandResults: View {
    let model: CommandModel
    let onRun: (CommandSuggestion) -> Void
    let onApply: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.input.trimmingCharacters(in: .whitespaces).isEmpty {
                label("建议")
                suggestionList(model.suggestions)
            } else {
                if !model.parse.isEmpty {
                    label("指令")
                    TokenChips(tokens: model.parse.tokens)
                }
                if let p = model.preview {
                    CommandPreviewCard(preview: p, parse: model.parse, isApplying: model.isApplying, onApply: onApply)
                        .padding(.top, ZTokens.Space.n4)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
                let rest = model.suggestions.filter { $0 != model.preview?.suggestion }
                if !rest.isEmpty {
                    label(model.preview == nil && model.parse.isEmpty ? "结果" : "更多")
                    suggestionList(rest)
                } else if model.preview == nil {
                    Text(verbatim: "无结果")
                        .zType(.body).foregroundStyle(ZTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZTokens.Space.n8)
                }
            }
        }
        .animation(reduceMotion ? nil : ZMotion.slow, value: model.preview)
        .animation(reduceMotion ? nil : ZMotion.standard, value: model.suggestions)
    }

    private func label(_ s: String) -> some View {
        Text(verbatim: s)
            .zType(.caption).foregroundStyle(ZTokens.Colors.textTertiary)
            .padding(.horizontal, HMetrics.homeInset + ZTokens.Space.n1)
            .padding(.top, ZTokens.Space.n6)
            .padding(.bottom, ZTokens.Space.n3)
            .accessibilityAddTraits(.isHeader)
    }

    private func suggestionList(_ list: [CommandSuggestion]) -> some View {
        ZCard(padding: 0, cornerRadius: ZTokens.Radius.overlay) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                    if i > 0 { ZDivider() }
                    Button { onRun(s) } label: { SuggestionRow(s: s) }
                        .buttonStyle(ZRowButtonStyle())
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
    }
}

/// 指令卡片（原型 `.parse .pc`）：小标题 + 值，依次淡入。
private struct TokenChips: View {
    let tokens: [CommandToken]

    var body: some View {
        // 换行排布：大字体下自动折行
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ZTokens.Space.n3) { chips }
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) { chips }
        }
        .padding(.horizontal, HMetrics.homeInset)
    }

    private var chips: some View {
        ForEach(tokens, id: \.self) { t in
            VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                Text(verbatim: t.kind.rawValue).zType(.caption).foregroundStyle(ZTokens.Colors.textTertiary)
                Text(verbatim: t.value).zType(.body).foregroundStyle(ZTokens.Colors.textPrimary)
            }
            .padding(.horizontal, ZTokens.Space.n4)
            .padding(.vertical, ZTokens.Space.n3)
            .zSurface(.raised, cornerRadius: ZTokens.Radius.surface)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SuggestionRow: View {
    let s: CommandSuggestion

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .frame(width: ZTokens.Space.n6)
            VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                Text(verbatim: s.title).zType(.body).foregroundStyle(ZTokens.Colors.textPrimary)
                if let sub = s.subtitle {
                    Text(verbatim: sub).zType(.caption).foregroundStyle(ZTokens.Colors.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(ZQuaternaryText())
        }
        .padding(.vertical, ZTokens.Space.n4)
        .padding(.horizontal, ZTokens.Space.n5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch s.kind {
        case .switchNode: "arrow.triangle.swap"
        case .switchMode: "arrow.triangle.branch"
        case .openNodeQuery: "magnifyingglass"
        case .testRule: "checklist"
        case .openPage: "square.grid.2x2"
        case .toggleConnection: "power"
        }
    }
}

// 指令结果区：token 卡片、主预览卡、建议列表、无结果。
// 空输入（契约 §16.d U24）：原型 SUG 四条示例短语，点按只填入输入框；引擎的空输入建议（如连接）列在其后。
// Raycast 式结果（规范 §9.5，设计评审 J-3）：按类型分组（指令 / 场景 / 节点 / 设置 / 规则测试，空组不显示），
// 行右侧对齐动作标签（应用 / 切换 / 打开 / 测试），第一行另显示 ⏎（回车执行第一行，见 CommandView.submit）；
// 每组最多 5 行，组末「显示全部 n 项」。
// 硬件键盘（J-3）：↑ / ↓ / Tab / ⇧Tab 在可见行间移动高亮（CommandTextField 的 UIKeyCommand），回车执行高亮行；
// 高亮行有底色并带 ⏎；没有高亮时回车照旧执行主预览或第一行。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct CommandResults: View {
    let model: CommandModel
    let onRun: (CommandSuggestion) -> Void
    let onApply: () -> Void
    var onFill: (String) -> Void = { _ in }
    /// 展开了「显示全部」的组（放在 CommandView，键盘移动要知道哪些行可见）。
    @Binding var expanded: Set<CommandGroup>
    /// 键盘高亮行的 key（`keyed` 的 key）；nil = 无高亮。
    var highlighted: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zStaticRendering) private var still

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.input.trimmingCharacters(in: .whitespaces).isEmpty {
                label(ZL.tr("建议"))
                exampleList(CommandModel.examples)
                if !model.suggestions.isEmpty {
                    label(ZL.tr("更多"))
                    suggestionList(model.suggestions)
                }
            } else {
                if !model.parse.isEmpty {
                    label(ZL.tr("指令"))
                    TokenChips(tokens: model.parse.tokens)
                }
                if let f = model.filterPreview {
                    CommandFilterCard(preview: f, isApplying: model.isApplying, onApply: onApply)
                        .padding(.top, ZTokens.Space.n4)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
                if let plan = model.plan {
                    CommandPlanCard(plan: plan, isApplying: model.isApplying, onApply: onApply)
                        .padding(.top, ZTokens.Space.n4)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
                if let p = model.preview {
                    CommandPreviewCard(preview: p, parse: model.parse, isApplying: model.isApplying, onApply: onApply)
                        .padding(.top, ZTokens.Space.n4)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
                let rest = Self.rest(model)
                if !rest.isEmpty {
                    let groups = Self.groups(rest)
                    let defaultKey = highlighted ?? (model.hasPrimary ? nil : groups.first?.items.first.map { Self.keyed([$0])[0].key })
                    ForEach(groups, id: \.group) { g in
                        label(g.group.title)
                        groupList(g, defaultKey: defaultKey)
                    }
                } else if !model.hasContent {
                    Text("无结果")
                        .zType(.body).foregroundStyle(ZColor.t3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZTokens.Space.n8)
                }
            }
        }
        .animation((reduceMotion || still) ? nil : ZMotion.slow, value: model.preview)
        .animation((reduceMotion || still) ? nil : ZMotion.slow, value: model.filterPreview)
        .animation((reduceMotion || still) ? nil : ZMotion.slow, value: model.plan)
        .animation((reduceMotion || still) ? nil : ZMotion.standard, value: model.suggestions)
    }

    private func label(_ s: String) -> some View {
        Text(verbatim: s)
            .zType(.footnote).foregroundStyle(ZColor.t3)
            .padding(.horizontal, HMetrics.homeInset + ZTokens.Space.n1)
            .padding(.top, ZTokens.Space.n6)
            .padding(.bottom, ZTokens.Space.n3)
            .accessibilityAddTraits(.isHeader)
    }

    /// 一组结果：最多 5 行，超出时组末「显示全部 n 项」。
    private func groupList(_ g: GroupedSuggestions, defaultKey: String?) -> some View {
        let showAll = expanded.contains(g.group) || g.items.count <= Self.groupLimit
        let shown = showAll ? g.items : Array(g.items.prefix(Self.groupLimit))
        return ZCard(padding: 0, cornerRadius: ZTokens.Radius.overlay) {
            VStack(spacing: 0) {
                ForEach(Self.keyed(shown), id: \.key) { item in
                    let s = item.suggestion
                    if item.index > 0 { ZDivider() }
                    Button { onRun(s) } label: {
                        SuggestionRow(s: s, isDefault: item.key == defaultKey, isHighlighted: item.key == highlighted)
                    }
                    .buttonStyle(ZRowButtonStyle())
                    .id(item.key)
                }
                if !showAll {
                    ZDivider()
                    Button { expanded.insert(g.group) } label: {
                        HStack {
                            Text(verbatim: ZL.s("显示全部 %@ 项", "\(g.items.count)"))
                                .zType(.footnote).foregroundStyle(ZAccentTextStyle())
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, ZTokens.Space.n4)
                        .padding(.horizontal, ZTokens.Space.n5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ZRowButtonStyle())
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
    }

    // MARK: 分组（纯函数，CommandView.submit 用同一顺序决定回车执行哪一行）

    nonisolated static let groupLimit = 5

    struct GroupedSuggestions {
        let group: CommandGroup
        let items: [CommandSuggestion]
    }

    /// 主预览卡之外的建议。
    static func rest(_ model: CommandModel) -> [CommandSuggestion] {
        model.suggestions.filter { $0 != model.preview?.suggestion }
    }

    /// 按固定组序分组，组内保持引擎给的顺序；空组不出现。
    nonisolated static func groups(_ list: [CommandSuggestion]) -> [GroupedSuggestions] {
        CommandGroup.allCases.compactMap { g in
            let items = list.filter { CommandGroup(kind: $0.kind) == g }
            return items.isEmpty ? nil : GroupedSuggestions(group: g, items: items)
        }
    }

    /// 回车执行的第一行（分组后的第一组第一行）。
    nonisolated static func firstRow(_ list: [CommandSuggestion]) -> CommandSuggestion? {
        groups(list).first?.items.first
    }

    /// 当前可见的结果行（组序 + 每组 5 行 / 已展开全部），key 与渲染一致。键盘移动按这个顺序。
    nonisolated static func visibleRows(_ list: [CommandSuggestion], expanded: Set<CommandGroup>) -> [KeyedSuggestion] {
        groups(list).flatMap { g -> [KeyedSuggestion] in
            let showAll = expanded.contains(g.group) || g.items.count <= groupLimit
            return keyed(showAll ? g.items : Array(g.items.prefix(groupLimit)))
        }
    }

    /// 键盘移动一步（↑ = −1，↓ / Tab = +1）后的高亮 key。不循环，停在两端。
    /// - 没有高亮时：有主预览卡（hasPrimary，回车默认应用预览）→ ↓ 到第一行；否则第一行已是默认 → ↓ 到第二行。
    /// - 有主预览卡时，从第一行再 ↑ 回到「无高亮」（回车 = 应用预览）。
    nonisolated static func moveHighlight(from current: String?, rows: [String], by step: Int, hasPrimary: Bool) -> String? {
        guard !rows.isEmpty, step != 0 else { return current }
        let floor = hasPrimary ? -1 : 0
        let at: Int = current.flatMap { rows.firstIndex(of: $0) } ?? floor
        let next = min(rows.count - 1, max(floor, at + (step > 0 ? 1 : -1)))
        return next < 0 ? nil : rows[next]
    }

    private func suggestionList(_ list: [CommandSuggestion]) -> some View {
        ZCard(padding: 0, cornerRadius: ZTokens.Radius.overlay) {
            VStack(spacing: 0) {
                // 以建议自身为 id（REVIEW-Q1 H-P2-16）：按下标会让增删动画错位到相邻行。
                ForEach(Self.keyed(list), id: \.key) { item in
                    let s = item.suggestion
                    if item.index > 0 { ZDivider() }
                    Button { onRun(s) } label: { SuggestionRow(s: s) }
                        .buttonStyle(ZRowButtonStyle())
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
    }

    /// 示例短语（原型 `.sugg`）：只有文字，点按填入输入框。
    private func exampleList(_ list: [String]) -> some View {
        ZCard(padding: 0, cornerRadius: ZTokens.Radius.overlay) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element) { i, text in
                    if i > 0 { ZDivider() }
                    Button { onFill(text) } label: {
                        HStack {
                            Text(verbatim: text).zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, ZTokens.Space.n4)
                        .padding(.horizontal, ZTokens.Space.n5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ZRowButtonStyle())
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
    }

    struct KeyedSuggestion {
        let key: String
        let index: Int
        let suggestion: CommandSuggestion
    }

    /// 稳定 id：kind|title|payload；同一建议重复出现时追加 #n 保证唯一。
    nonisolated static func keyed(_ list: [CommandSuggestion]) -> [KeyedSuggestion] {
        var seen: [String: Int] = [:]
        return list.enumerated().map { i, s in
            let base = "\(s.kind)|\(s.title)|\(s.payload)"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return KeyedSuggestion(key: n == 0 ? base : "\(base)#\(n)", index: i, suggestion: s)
        }
    }
}

/// 指令卡片（原型 `.parse .pc`）：小标题 + 值，依次淡入。
@MainActor
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
                Text(verbatim: ZL.tr(t.kind.rawValue)).zType(.caption).foregroundStyle(ZColor.t3)
                Text(verbatim: t.value).zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
            }
            .padding(.horizontal, ZTokens.Space.n4)
            .padding(.vertical, ZTokens.Space.n3)
            .zSurface(.raised, cornerRadius: ZTokens.Radius.surface)
            .accessibilityElement(children: .combine)
        }
    }
}

/// 指令结果的组（规范 §9.5 固定组序）。
enum CommandGroup: Int, CaseIterable, Hashable, Sendable {
    case command, scene, node, settings, ruleTest

    init(kind: CommandKind) {
        switch kind {
        case .switchMode, .toggleConnection: self = .command
        case .switchNode: self = .scene
        case .openNodeQuery: self = .node
        case .openPage: self = .settings
        case .testRule: self = .ruleTest
        }
    }

    var title: String {
        switch self {
        case .command: ZL.tr("指令")
        case .scene: ZL.tr("场景")
        case .node: ZL.tr("节点")
        case .settings: ZL.tr("设置")
        case .ruleTest: ZL.tr("规则测试")
        }
    }
}

@MainActor
private struct SuggestionRow: View {
    let s: CommandSuggestion
    /// 第一行 / 键盘高亮行（回车执行）：动作标签旁显示 ⏎ 键帽。
    var isDefault = false
    /// 硬件键盘高亮（J-3）：整行 screen.pressed 底色。
    var isHighlighted = false

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(ZColor.t3)
                .frame(width: ZTokens.Space.n6)
            VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                Text(verbatim: s.title).zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
                if let sub = s.subtitle {
                    Text(verbatim: sub).zType(.caption).foregroundStyle(ZColor.t3)
                }
            }
            Spacer(minLength: ZTokens.Space.n3)
            // 动作标签：回车 / 轻点会发生什么（footnote、accent.text、无底色）。
            Text(verbatim: action)
                .zType(.footnote)
                .foregroundStyle(ZAccentTextStyle())
                .fixedSize()
            if isDefault {
                Image(systemName: "return")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ZColor.t2)
                    .padding(.horizontal, ZTokens.Space.n2)
                    .padding(.vertical, ZTokens.Space.n1 / 2)
                    .background(RoundedRectangle(cornerRadius: ZTokens.Space.n1, style: .continuous)
                        .strokeBorder(ZTokens.Colors.screenHl2, lineWidth: 1))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, ZTokens.Space.n4)
        .padding(.horizontal, ZTokens.Space.n5)
        .background(isHighlighted ? ZTokens.Colors.screenPressed : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityHint(isDefault ? Text("按回车执行") : Text(verbatim: ""))
    }

    /// 动作标签（规范 §9.5）：指令 = 应用，场景节点 = 切换，打开节点搜索 / 页面 = 打开，规则测试 = 测试。
    private var action: String {
        switch s.kind {
        case .switchMode, .toggleConnection: ZL.tr("应用")
        case .switchNode: ZL.tr("切换")
        case .openNodeQuery, .openPage: ZL.tr("打开")
        case .testRule: ZL.tr("测试")
        }
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

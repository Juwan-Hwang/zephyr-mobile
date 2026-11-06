// RulesView — 规则页（原型 22 规则 / 23 规则：已拦截）。
// 总数大字 → “7 层 · 已编译 · 磁盘占用 1.9 GB” → 测试卡（即时 testRule）→ 匹配顺序 8 行（命中行高亮）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

public struct RulesView: View {
    @State private var model: RulesModel
    @State private var adding = false

    /// - Parameters:
    ///   - query: 预填的测试输入（Route.rules(query:)、指令里的域名）；nil 用原型默认 chat.openai.com
    public init(engine: any ZephyrEngine, query: String? = nil) {
        _model = State(initialValue: RulesModel(engine: engine, query: query))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LPageHeader(title: "规则", number: model.stats?.total, unit: "条", subtitle: model.subtitle)
                RuleTestCard(input: $model.input, steps: model.steps, took: model.tookText, invalid: model.invalid)
                    .padding(.horizontal, LStyle.margin)
                    .padding(.top, ZTokens.Space.n5)
                LSectionHeader("匹配顺序", trailing: "从上到下")
                layers
                Text("规则集在设备上编译为只读索引，按需从磁盘读取。订阅更新时，覆写保持不变。")
                    .lFootnoteStyle()
            }
            .padding(.bottom, ZTokens.Space.n8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LStyle.pageBackground.ignoresSafeArea())
        .lAccent(from: model.engine)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                }
                .accessibilityLabel("添加覆写")
            }
        }
        .sheet(isPresented: $adding) { RuleAddSheet() }
        .task { await model.start() }
        .onChange(of: model.input) { model.runTest() }
    }

    @ViewBuilder private var layers: some View {
        if let stats = model.stats {
            VStack(spacing: 0) {
                ForEach(Array(stats.layers.enumerated()), id: \.element.id) { i, layer in
                    if i > 0 { LDivider() }
                    RuleLayerRow(ordinal: i + 1, name: layer.name, note: layer.note, kind: layer.kind,
                                 count: ZFormat.count(layer.count), isHit: model.hitRow == i)
                }
                LDivider()
                RuleLayerRow(ordinal: stats.layers.count + 1, name: "其余流量", note: "MATCH", kind: nil,
                             count: "其他", isHit: model.hitRow == stats.layers.count)
            }
            .lCard()
            .padding(.horizontal, LStyle.margin)
        } else {
            RoundedRectangle(cornerRadius: LStyle.cardRadius, style: .continuous)
                .fill(ZTokens.Colors.bgMuted)
                .frame(height: LStyle.rowMinHeight * 8)
                .padding(.horizontal, LStyle.margin)
                .redacted(reason: .placeholder)
        }
    }
}

#Preview("规则") {
    NavigationStack { RulesView(engine: MockEngine(seed: 0, clock: .frozen941)) }
}

#Preview("已拦截") {
    NavigationStack { RulesView(engine: MockEngine(seed: 0, clock: .frozen941), query: "ads.doubleclick.net") }
}

#Preview("浅色 · 大字体") {
    NavigationStack { RulesView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .accessibility2)
}

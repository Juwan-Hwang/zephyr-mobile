// NodesView — 节点页（原型 20 节点 / 21 搜索节点）。性能标杆：1e8 行虚拟列表。
//
// 页头（标题、总数、副标题）+ 搜索 + 地区 chips 为 SwiftUI；列表为 UIKit（NodeListView），
// 两者之间只传“结果代数”，滚动、分页、测速全部在 UIKit 内完成，不触发 SwiftUI 重算。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

@MainActor
public struct NodesView: View {
    @State private var model: NodesModel
    @State private var selected: NodeSummary?

    /// - Parameters:
    ///   - engine: 引擎（App 注入 CoreEngine，预览/快照注入 MockEngine）
    ///   - query: 初始搜索词，"" = 全部（Route.nodes(query:)、指令“东京 IPLC”）
    public init(engine: any ZephyrEngine, query: String = "") {
        _model = State(initialValue: NodesModel(engine: engine, query: query))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "节点", number: model.index.map { ZFormat.count($0.total) }, unit: "个", subtitle: model.subtitle)
            ZTextField("地区、城市或线路", text: $model.query, trailing: model.query.isEmpty ? nil : model.queryInfo)
                .padding(.horizontal, PageMetrics.margin)
                .padding(.top, ZTokens.Space.n5)
            RegionChips(sections: model.chips, selected: model.selectedChip) { model.select(chip: $0) }
                .padding(.top, ZTokens.Space.n3)
            NodeListRepresentable(model: model, rowMap: model.rowMap, generation: model.generation,
                                  accent: model.accent.color) { selected = $0 }
                .overlay {
                    if model.isEmptyResult { NodesEmptyState(query: model.query) }
                }
                .padding(.top, ZTokens.Space.n4)
                .ignoresSafeArea(.container, edges: .bottom)
                .accessibilityLabel("节点列表")
        }
        .zPageBackground()
        .zAccent(model.accent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { jumpMenu }
        }
        .task { await model.start() }
        .onChange(of: model.query) { model.runQuery(debounced: true) }
        .sheet(item: $selected) { node in
            NodeDetailSheet(engine: model.engine, node: node) { model.store.testVisible([node]) }
        }
    }

    /// 原型右上角“排序”按钮：契约暂无排序，提供“回到顶部 / 跳到地区”。
    private var jumpMenu: some View {
        Menu {
            Button("回到顶部", systemImage: "arrow.up.to.line") { model.jumpToTop() }
            Section("跳到地区") {
                ForEach(model.rowMap.sections, id: \.region) { s in
                    Button("\(s.region) \(s.name) · \(CompactCount.chip(s.count))") { model.jump(toSection: s.region) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.medium))
                .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
        }
        .accessibilityLabel("跳转")
    }
}

#Preview("节点") {
    NavigationStack { NodesView(engine: MockEngine(seed: 0, clock: .frozen941)) }
}

#Preview("搜索 东京 IPLC") {
    NavigationStack { NodesView(engine: MockEngine(seed: 0, clock: .frozen941), query: "东京 IPLC") }
}

#Preview("浅色 · 大字体") {
    NavigationStack { NodesView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .accessibility2)
}

// NodesModel — 节点页的页面模型（@Observable，只放会驱动 SwiftUI 的少量状态）。
//
// 高频数据（页缓存、延迟、滚动位置）在 NodeRowStore / NodeListView 里，不经过 Observation。

import Observation
import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
@Observable
final class NodesModel {
    @ObservationIgnored let engine: any ZephyrEngine
    @ObservationIgnored let store: NodeRowStore
    /// 列表视图（用于菜单“跳到地区”）。弱引用，生命周期归 SwiftUI。
    @ObservationIgnored weak var listView: NodeListView?

    /// 搜索框文本（双向绑定）。变化后由视图调用 runQuery()。
    var query: String
    private(set) var index: NodeIndex?
    private(set) var subscriptionCount: Int32?
    private(set) var result: NodeQueryResult?
    private(set) var rowMap = NodeRowMap.empty
    /// 每次新结果 +1，通知 UIKit 列表重置到顶部。
    private(set) var generation = 0
    private(set) var accent: ZTokens.Accent = .blue
    private(set) var failed = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(engine: any ZephyrEngine, query: String) {
        self.engine = engine
        self.store = NodeRowStore(engine: engine)
        self.query = query
    }

    /// 由 .task 调用：载入索引与订阅数，启动延迟流，跑首个查询，然后常驻监听强调色。
    func start() async {
        guard !started else { return }
        started = true
        store.startLatencyStream()
        runQuery()
        async let idx = engine.nodeIndex()
        async let subs = engine.subscriptionsSummary()
        let (i, s) = await (idx, subs)
        index = i
        subscriptionCount = s.count
        store.setTestedBase(i.testedCount)
        listView?.footer.set(tested: store.testedCount)
        for await settings in engine.settings() {
            let a = ZTokens.Accent(rawValue: settings.accent.rawValue) ?? .blue
            if a != accent { accent = a }
        }
    }

    func runQuery() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.engine.queryNodes(query: q)
                guard !Task.isCancelled,
                      q == self.query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.apply(r)
            } catch {
                guard !Task.isCancelled else { return }
                self.failed = true
            }
        }
    }

    private func apply(_ r: NodeQueryResult) {
        failed = false
        result = r
        rowMap = NodeRowMap(sections: r.sections.map { ($0.region, $0.name, $0.count) })
        store.reset(token: r.token, total: r.total, highlights: r.highlights)
        generation &+= 1
    }

    func select(chip region: String) {
        query = region
    }

    func jump(toSection region: String) {
        guard let s = rowMap.sections.first(where: { $0.region == region }) else { return }
        listView?.jump(toRow: s.headerRow)
    }

    func jumpToTop() { listView?.jump(toRow: 0) }

    // MARK: 派生文案

    /// “来自 214 个订阅 · 15 个地区”
    var subtitle: String? {
        guard let index else { return nil }
        let subs = subscriptionCount.map { "来自 \($0) 个订阅 · " } ?? ""
        return "\(subs)\(index.sections.count) 个地区"
    }

    /// 搜索框右侧：“220,412 个 · 0.70 ms”（原型：< 1ms 两位小数，否则一位）。
    var queryInfo: String? {
        guard let r = result, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let ms = Double(r.tookMicros) / 1000
        return "\(ZFormat.count(r.total)) 个 · \(String(format: ms < 1 ? "%.2f" : "%.1f", ms)) ms"
    }

    /// 地区 chips：全部 + 前 8 个地区（原型 RG.slice(0,8)）。
    var chips: [RegionSection] { Array((index?.sections ?? []).prefix(8)) }

    var selectedChip: String { query.trimmingCharacters(in: .whitespaces) }

    var isEmptyResult: Bool { result.map { $0.total == 0 } ?? false }
}

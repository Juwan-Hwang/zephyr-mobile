// NodesModel — 节点页的页面模型（@Observable，只放会驱动 SwiftUI 的少量状态）。
//
// 高频数据（页缓存、延迟、滚动位置）在 NodeRowStore / NodeListView 里，不经过 Observation。

import Network
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
    /// 节点页判断句的数（契约 §18.a）：同一次 nodeFunnel 的 reachable / tested；nil = 取不到，只写「已检测 N」。
    private(set) var funnel: NodeFunnel?
    @ObservationIgnored private var funnelRequested = false

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
        updateFooterTested()
        let pathTask = Task { @MainActor [weak self] in
            for await path in NWPathMonitor() {
                guard let self else { return }
                self.metered = Self.isMetered(path)
                self.updateAutoTestGate()
            }
        }
        defer { pathTask.cancel() }
        for await settings in engine.settings() {
            if !funnelRequested {
                funnelRequested = true
                let maxAge = SceneSheet.funnelMaxAgeMs(settings)
                Task { [weak self] in
                    guard let self else { return }
                    // thresholdMs 不影响 reachable（契约 §18.a），传 latency.threshold-slow。
                    let f = await self.engine.nodeFunnel(maxAgeMs: maxAge, thresholdMs: Int32(ZTokens.LatencyThreshold.slow))
                    self.funnel = f
                    self.updateFooterTested()
                }
            }
            let a = ZTokens.Accent(rawValue: settings.accent.rawValue) ?? .blue
            if a != accent { accent = a }
            testOnWifiOnly = settings.testOnWifiOnly
            updateAutoTestGate()
        }
    }

    // MARK: 仅在 Wi‑Fi 下测速（REVIEW-Q2 X-P1-5）

    @ObservationIgnored private var testOnWifiOnly = true
    /// 当前路径是否计费（蜂窝、个人热点、低数据模式）。未知时按不计费处理，避免首帧误禁。
    @ObservationIgnored private var metered = false

    nonisolated static func isMetered(_ path: NWPath) -> Bool { path.isExpensive || path.isConstrained }

    /// 滚动自动测速是否允许：纯函数，便于单测。
    nonisolated static func autoTestAllowed(wifiOnly: Bool, metered: Bool) -> Bool { !(wifiOnly && metered) }

    private func updateAutoTestGate() {
        store.autoTestAllowed = Self.autoTestAllowed(wifiOnly: testOnWifiOnly, metered: metered)
    }

    /// 最近一次真正发给引擎的查询（chip 立即查后，随之而来的 onChange 去抖查询据此跳过）。
    @ObservationIgnored private var issuedQuery: String?

    /// 输入框改动走去抖（REVIEW L-P1-3：避免每个按键、拼音每个字母都打全量查询）；chip / 首次加载立即查。
    func runQuery(debounced: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if debounced, q == issuedQuery { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: 140_000_000)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            self.issuedQuery = q
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
        updateFooterTested()
    }

    func select(chip region: String) {
        query = region
        runQuery()
    }

    func jump(toSection region: String) {
        guard let s = rowMap.sections.first(where: { $0.region == region }) else { return }
        listView?.jump(toRow: s.headerRow)
    }

    func jumpToTop() { listView?.jump(toRow: 0) }

    // MARK: 派生文案

    /// “来自 214 个订阅　15 个地区”：两项用宽空格分开，不用中点（规范 §9.2：每屏只一处中点，留给判断句）。
    var subtitle: String? {
        guard let index else { return nil }
        let regions = ZL.f("%lld 个地区", Int64(index.sections.count))
        guard let n = subscriptionCount else { return regions }
        return ZL.f("来自 %lld 个订阅", Int64(n)) + "\u{2003}" + regions
    }

    /// 是否显示判断句：只在全部节点（非搜索）且索引载入成功、库非空时（契约 §18.a）。
    private var showsJudgement: Bool {
        guard let index, index.total > 0 else { return false }
        return query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func updateFooterTested() {
        listView?.footer.showsTested = !showsJudgement
    }

    /// 节点页判断句（规范 §9.4，契约 §18.a）：「可连通 x · 已检测 N」；reachable 为 0 时数字用 red-text，否则 t1；整行 t2。
    var judgement: AttributedString? {
        guard showsJudgement, let index else { return nil }
        if let f = funnel, f.tested > 0 {
            let r = ZFormat.count(Int64(f.reachable))
            var a = AttributedString(ZL.s("可连通 %1$@ · 已检测 %2$@", r, ZFormat.count(Int64(f.tested))))
            if let range = a.range(of: r) {
                a[range].foregroundColor = f.reachable == 0 ? ZTokens.Colors.screenRedText : ZTokens.Colors.screenT1
            }
            return a
        }
        if funnel == nil, index.testedCount > 0 {
            return AttributedString(ZL.s("已检测 %@", ZFormat.count(index.testedCount)))
        }
        return AttributedString(ZL.tr("尚未检测，停止滚动后自动测可见节点"))
    }

    /// 搜索框右侧：“220,412 个 · 0.70 ms”（原型：< 1ms 两位小数，否则一位）。
    var queryInfo: String? {
        guard let r = result, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let ms = Double(r.tookMicros) / 1000
        return ZL.s("%@ 个 · %@ ms", ZFormat.count(r.total), String(format: ms < 1 ? "%.2f" : "%.1f", ms))
    }

    /// 地区 chips：全部 + 前 8 个地区（原型 RG.slice(0,8)）。
    var chips: [RegionSection] { Array((index?.sections ?? []).prefix(8)) }

    var selectedChip: String { query.trimmingCharacters(in: .whitespaces) }

    var isEmptyResult: Bool { result.map { $0.total == 0 } ?? false }
}

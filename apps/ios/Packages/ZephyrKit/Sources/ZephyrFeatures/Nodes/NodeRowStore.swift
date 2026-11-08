// NodeRowStore — 节点列表的数据层：按页拉取（engine.nodeRows）、LRU 缓存、延迟覆盖层与可见行测速。
//
// 不是 @Observable：它由 UIKit 列表直接驱动（回调刷新可见 cell），避免每页到达都触发 SwiftUI 重算。
// 全部在主线程；引擎调用经 async 跳出主线程，结果回主线程后核对 token，过期结果直接丢弃。

import Foundation
import ZephyrKit

@MainActor
final class NodeRowStore {
    enum LatencyState: Equatable {
        case value(Int32)   // -1 = 超时
        case testing
    }

    /// 每页节点数（契约 limit ≤ 500）。128 行 ≈ 6.6 屏（52pt），在缓存粒度与请求次数间折中。
    static let pageSize: Int64 = 128
    /// 缓存页数：96 页 ≈ 12k 节点 ≈ 1.5 MB。
    static let cachePages = 96
    /// 同时在途的页请求上限，防止索引条拖动时洪泛。
    static let maxInFlight = 6
    /// 一次 testLatency 最多 100 个（契约）。
    static let maxTestBatch = 100

    private let engine: any ZephyrEngine
    private(set) var token: Int64 = -1
    private(set) var total: Int64 = 0
    private(set) var highlights: [String] = []
    private var pages = LRUCache<Int64, [NodeSummary]>(capacity: NodeRowStore.cachePages)
    private var inFlight: Set<Int64> = []
    /// 测得/测试中的延迟。上限约 50k，超过时整体清空（只影响本次会话的覆盖显示，缓存值仍由引擎给出）。
    private var latency: [NodeId: LatencyState] = [:]
    nonisolated(unsafe) private var latencyTask: Task<Void, Never>?

    /// 基础已检测数（NodeIndex.testedCount）+ 本次会话新测的数量。
    private(set) var testedBase: Int64 = 0
    private(set) var testedSession: Int64 = 0
    var testedCount: Int64 { testedBase + testedSession }

    /// 某页到达：参数为页下标。
    var onPageLoaded: ((Int64) -> Void)?
    /// 延迟更新：参数为受影响的节点 id。
    var onLatencyChanged: ((Set<NodeId>) -> Void)?

    init(engine: any ZephyrEngine) {
        self.engine = engine
    }

    deinit { latencyTask?.cancel() }

    /// 订阅 latencyUpdates（只启动一次）。
    func startLatencyStream() {
        guard latencyTask == nil else { return }
        let stream = engine.latencyUpdates()
        latencyTask = Task { @MainActor [weak self] in
            for await batch in stream {
                guard let self else { return }
                self.apply(batch)
            }
        }
    }

    func setTestedBase(_ n: Int64) { testedBase = n }

    /// 换一个结果集（新查询）。清空页缓存，延迟覆盖层保留（同一节点的测速结果跨查询仍有效）。
    func reset(token: Int64, total: Int64, highlights: [String]) {
        self.token = token
        self.total = total
        self.highlights = highlights
        pages.removeAll()
        inFlight.removeAll()
    }

    // MARK: 读取

    /// 序号处的节点；未缓存返回 nil（cell 显示骨架，随后 onPageLoaded 刷新）。
    func node(atOrdinal ordinal: Int64) -> NodeSummary? {
        guard ordinal >= 0, ordinal < total else { return nil }
        let p = ordinal / Self.pageSize
        guard let rows = pages.value(for: p) else { return nil }
        let i = Int(ordinal - p * Self.pageSize)
        return i < rows.count ? rows[i] : nil
    }

    /// 显示用延迟：覆盖层优先，其次引擎缓存值。
    func latencyState(for node: NodeSummary) -> LatencyState? {
        if let s = latency[node.id] { return s }
        return node.latencyMs.map { .value($0) }
    }

    // MARK: 预取

    /// 确保覆盖 ordinals 的页已缓存或在途。`ahead` 为滚动方向（+1 向下，-1 向上，0 静止）。
    func ensure(ordinals: Range<Int64>, ahead: Int) {
        guard token >= 0, total > 0, !ordinals.isEmpty else { return }
        let lo = max(0, ordinals.lowerBound), hi = min(total, ordinals.upperBound)
        guard lo < hi else { return }
        let first = lo / Self.pageSize, last = (hi - 1) / Self.pageSize
        // 先可见页，再方向上的预取页（各 2 页），最后反方向 1 页。
        var wanted: [Int64] = Array(first...last)
        let maxPage = (total - 1) / Self.pageSize
        let fwd: [Int64] = ahead >= 0 ? [last + 1, last + 2, first - 1] : [first - 1, first - 2, last + 1]
        wanted += fwd.filter { $0 >= 0 && $0 <= maxPage }
        for (n, p) in wanted.enumerated() {
            if pages.contains(p) || inFlight.contains(p) { continue }
            // 可见页总是请求；预取页受在途上限约束。
            if n > (last - first) && inFlight.count >= Self.maxInFlight { break }
            load(page: p)
        }
    }

    private func load(page p: Int64) {
        let tk = token
        inFlight.insert(p)
        let offset = p * Self.pageSize
        let limit = Int32(min(Self.pageSize, total - offset))
        let engine = self.engine
        Task { @MainActor [weak self] in
            let result = try? await engine.nodeRows(token: tk, offset: offset, limit: limit)
            guard let self, self.token == tk else { return }
            self.inFlight.remove(p)
            guard let result else { return }
            self.pages.insert(result.rows, for: p)
            self.onPageLoaded?(p)
        }
    }

    // MARK: 测速

    /// 停止滚动 400ms 后：对可见、无缓存延迟的节点测速。返回实际提交的 id（已标记为测试中）。
    @discardableResult
    func testVisible(_ nodes: [NodeSummary]) -> [NodeId] {
        var ids: [NodeId] = []
        for n in nodes where ids.count < Self.maxTestBatch {
            if latency[n.id] != nil || n.latencyMs != nil { continue }
            latency[n.id] = .testing
            ids.append(n.id)
        }
        guard !ids.isEmpty else { return [] }
        let engine = self.engine
        let submitted = ids
        Task.detached(priority: .utility) { [weak self] in
            await engine.testLatency(ids: submitted)
            // 引擎没给结果的（不能测的协议、批次失败）退回「未测」，不要一直显示 ···
            await self?.clearTesting(submitted)
        }
        onLatencyChanged?(Set(ids))
        return ids
    }

    private func clearTesting(_ ids: [NodeId]) {
        var changed = Set<NodeId>()
        for id in ids where latency[id] == .testing {
            latency[id] = nil
            changed.insert(id)
        }
        if !changed.isEmpty { onLatencyChanged?(changed) }
    }

    private func apply(_ batch: [LatencyUpdate]) {
        guard !batch.isEmpty else { return }
        if latency.count > 50_000 { latency.removeAll(keepingCapacity: true) }
        var changed = Set<NodeId>()
        changed.reserveCapacity(batch.count)
        for u in batch {
            if case .value = latency[u.id] {} else { testedSession += 1 }
            latency[u.id] = .value(u.latencyMs)
            changed.insert(u.id)
        }
        onLatencyChanged?(changed)
    }
}

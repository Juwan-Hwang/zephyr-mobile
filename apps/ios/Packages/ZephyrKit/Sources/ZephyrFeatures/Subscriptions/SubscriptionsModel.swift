// SubscriptionsModel — 订阅页模型：订阅流、单个/全部更新、删除、“更新前显示更改”的预览确认。
//
// 更新流程（契约 §7）：
//   设置 showChangesBeforeUpdate = false → 直接 updateSubscription / updateAll，结果以吐司提示；
//   设置 showChangesBeforeUpdate = true  → 先 previewUpdate（全部时逐个预览、限并发、合计），
//                                         弹出确认（pendingReview），用户点“更新”后再执行。

import Foundation
import Observation
import ZephyrDesign
import ZephyrKit

@MainActor
@Observable
final class SubscriptionsModel {
    /// 待确认的更新。
    struct Review: Identifiable {
        enum Target: Equatable {
            case one(Subscription)
            case all(count: Int)
        }
        let id = UUID()
        var target: Target
        var diff: SubscriptionDiff
    }

    @ObservationIgnored let engine: any ZephyrEngine
    @ObservationIgnored let now: @Sendable () -> Int64
    let settings: SettingsStore

    private(set) var subscriptions: [Subscription] = []
    private(set) var loaded = false
    /// 正在更新（或预览）的订阅 id。
    private(set) var updating: Set<String> = []
    private(set) var isUpdatingAll = false
    var review: Review?
    /// 左滑“删除”后待确认的订阅。
    var deleting: Subscription?
    /// 成功 / 结果提示（底部吐司）。
    var toast: ZToastItem?
    /// 失败提示（顶部横幅，REVIEW L-P2-11：错误一律走横幅）。
    var error: PageError?

    /// 全部预览时的并发上限：真实引擎的 previewUpdate 会拉取远端订阅。
    static let previewConcurrency = 6
    /// 7 天内到期或用量 ≥ 80% 记为警告（原型 Orbit 黄条）。
    static let warnMillis: Int64 = 7 * 86_400_000
    static let warnUsage = 0.8

    init(engine: any ZephyrEngine, now: @escaping @Sendable () -> Int64) {
        self.engine = engine
        self.now = now
        self.settings = SettingsStore(engine: engine)
    }

    func start() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeSubscriptions() }
            group.addTask { await self.settings.start() }
        }
    }

    private func observeSubscriptions() async {
        for await subs in engine.subscriptions() {
            subscriptions = subs
            loaded = true
        }
    }

    // MARK: 派生

    /// 有流量信息的订阅（流量卡逐个展示）。
    var metered: [Subscription] { subscriptions.filter { $0.totalBytes != nil || $0.remainingBytes != nil } }
    /// 其余订阅（流量卡最后一行“其他 212 个”）。
    var others: [Subscription] { subscriptions.filter { $0.totalBytes == nil && $0.remainingBytes == nil } }
    var othersNodeCount: Int64 { others.reduce(0) { $0 + $1.nodeCount } }

    /// 最近一次带 diff 的更新（diff 卡）。
    var latestUpdate: Subscription? {
        subscriptions.filter { $0.lastDiff != nil }.max { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }
    }

    /// “个 · 每 12 小时更新”
    var headerUnit: String {
        guard let h = settings.settings?.autoUpdateHours else { return ZL.tr("个") }
        return ZL.f("个 · 每 %lld 小时更新", Int64(h))
    }

    func usage(_ s: Subscription) -> Double? {
        guard let t = s.totalBytes, t > 0 else { return nil }
        let used = s.usedBytes ?? (s.remainingBytes.map { t - $0 } ?? 0)
        return min(1, max(0, Double(used) / Double(t)))
    }

    func isWarning(_ s: Subscription) -> Bool {
        if let e = s.expiresAt, e - now() < Self.warnMillis { return true }
        return (usage(s) ?? 0) >= Self.warnUsage
    }

    /// “8,204 个节点 · 26 天后到期”；更新中为“正在更新…”。
    func detail(_ s: Subscription) -> String {
        if updating.contains(s.id) || isUpdatingAll { return ZL.tr("正在更新…") }
        var parts = [ZL.s("%@ 个节点", ZFormat.count(s.nodeCount))]
        if let e = s.expiresAt { parts.append(ZFormat.expiry(e, now: now())) }
        else if let u = s.updatedAt { parts.append(ZL.s("%@更新", ZFormat.relative(u, now: now()))) }
        return parts.joined(separator: " · ")
    }

    // MARK: 更新

    private var reviewFirst: Bool { settings.settings?.showChangesBeforeUpdate ?? false }

    /// 左滑“更新”。
    func update(_ sub: Subscription) async {
        guard !updating.contains(sub.id) else { return }
        guard reviewFirst else { return await perform(sub) }
        updating.insert(sub.id)
        defer { updating.remove(sub.id) }
        do {
            let diff = try await engine.previewUpdate(id: sub.id)
            review = Review(target: .one(sub), diff: diff)
        } catch { report(error) }
    }

    /// 下拉更新全部。
    func refreshAll() async {
        guard !isUpdatingAll, !subscriptions.isEmpty else { return }
        guard reviewFirst else { return await performAll() }
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        do {
            let diff = try await previewAll(subscriptions.map(\.id))
            review = Review(target: .all(count: subscriptions.count), diff: diff)
        } catch { report(error) }
    }

    /// 确认卡“更新”。
    func confirm(_ r: Review) async {
        review = nil
        switch r.target {
        case .one(let sub): await perform(sub)
        case .all: await performAll()
        }
    }

    private func perform(_ sub: Subscription) async {
        updating.insert(sub.id)
        defer { updating.remove(sub.id) }
        do {
            let d = try await engine.updateSubscription(id: sub.id)
            toast = ZToastItem(ZL.s("已更新 %@：%@ / %@ 节点", sub.name, Self.signed(d.addedNodes, plus: true), Self.signed(d.removedNodes, plus: false)))
        } catch { report(error) }
    }

    private func performAll() async {
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        do {
            let diffs = try await engine.updateAll()
            toast = ZToastItem(ZL.f("已更新 %lld 个订阅", Int64(diffs.count)))
        } catch { report(error) }
    }

    private func previewAll(_ ids: [String]) async throws -> SubscriptionDiff {
        let engine = self.engine
        var total = SubscriptionDiff(addedNodes: 0, removedNodes: 0, ruleChanges: 0, overridesKept: true, scenesRetested: false)
        var start = 0
        while start < ids.count {
            let batch = Array(ids[start..<min(start + Self.previewConcurrency, ids.count)])
            start += batch.count
            try await withThrowingTaskGroup(of: SubscriptionDiff.self) { group in
                for id in batch { group.addTask { try await engine.previewUpdate(id: id) } }
                for try await d in group { total = Self.merge(total, d) }
            }
        }
        return total
    }

    nonisolated static func merge(_ a: SubscriptionDiff, _ b: SubscriptionDiff) -> SubscriptionDiff {
        SubscriptionDiff(addedNodes: a.addedNodes + b.addedNodes, removedNodes: a.removedNodes + b.removedNodes,
                         ruleChanges: a.ruleChanges + b.ruleChanges, overridesKept: a.overridesKept && b.overridesKept,
                         scenesRetested: a.scenesRetested || b.scenesRetested)
    }

    /// "+1,204" / "−318"（U+2212 减号，与原型一致）。
    nonisolated static func signed(_ n: Int64, plus: Bool) -> String {
        (plus ? "+" : "\u{2212}") + ZFormat.count(n)
    }

    // MARK: 删除 / 导入

    func delete(_ sub: Subscription) async {
        deleting = nil
        do {
            try await engine.deleteSubscription(id: sub.id)
            toast = ZToastItem(ZL.s("已删除 %@", sub.name))
        } catch { report(error) }
    }

    func didImport(_ sub: Subscription) {
        toast = ZToastItem(ZL.s("已添加 %@（%@ 个节点）", sub.name, ZFormat.count(sub.nodeCount)))
    }

    func report(_ error: Error) {
        if let e = PageError.from(error, fallback: ZL.tr("操作失败")) { self.error = e }
    }
}

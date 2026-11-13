// ZephyrEngine —— contract/zephyr-engine.md v0 的 Swift 形态。
// 方法名、参数标签照抄契约；Stream = AsyncStream；全部方法线程安全，可在任意线程调用。
// 实现：ZephyrMock.MockEngine（确定性数据）、ZephyrCore.CoreEngine（UniFFI，仅 Apple 平台）。

import Foundation

public protocol ZephyrEngine: AnyObject, Sendable {

    // MARK: §1 连接与模式
    /// 立即发当前值，之后变化即发。
    func connectionState() -> AsyncStream<ConnectionState>
    /// 平台层先启动 VPN/NE，再调此方法。
    func connect() async throws
    func disconnect() async throws
    func setMode(mode: ProxyMode) async throws
    func setGlobalNode(id: NodeId) async throws -> ExitChange

    // MARK: §2 流量与用量
    /// 1 Hz；未连接时不发。
    func traffic() -> AsyncStream<TrafficSample>
    /// 迷你曲线回填，最多 300。
    func recentTraffic(seconds: Int32) -> [TrafficSample]
    func usageToday() async -> UsageSummary

    // MARK: §3 场景
    func scenes() -> AsyncStream<[Scene]>
    /// 场景出口自动探测的结果（契约 v0.2 场景自动切换）。只在隧道连接期间有事件；不支持的引擎返回立即结束的流。
    func sceneFailovers() -> AsyncStream<SceneFailoverNotice>
    /// 按延迟排序，最多 50。
    func sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary]
    func previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ExitChange
    /// UI 支持"撤销"：再 apply 旧节点。
    func applySceneChange(sceneId: String, nodeId: NodeId) async throws
    func retestScene(sceneId: String) async throws -> Scene
    /// 契约 §14.z：来源分段（优选 = auto 立即换到最优；manual / subscriptionGroup 只记录）。
    func setSceneSource(sceneId: String, source: SceneSource) async throws
    /// 契约 §13：连接轨迹"本次连接 / 始终应用"。target = .unchanged 清除；persistent = false 只在本次运行有效。
    func overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Bool) async throws

    // MARK: §4 策略组
    func policyGroups() -> AsyncStream<[PolicyGroup]>
    /// limit ≤ 500
    func groupMembers(group: String, offset: Int32, limit: Int32) async throws -> NodePage
    func selectInGroup(group: String, nodeId: NodeId) async throws
    /// 只测该组，结果经 latencyUpdates 推送。
    func testGroup(group: String) async throws

    // MARK: §5 节点库
    func nodeIndex() async -> NodeIndex
    /// "" = 全部；绝不扫全表。
    func queryNodes(query: String) async throws -> NodeQueryResult
    /// offset 为节点序号（不含分区头），limit ≤ 500。
    func nodeRows(token: Int64, offset: Int64, limit: Int32) async throws -> NodePage
    func node(id: NodeId) async throws -> NodeDetail
    /// 只测可见行（UI 停止滚动 400ms 后调用），≤ 100 个。
    func testLatency(ids: [NodeId]) async
    func latencyUpdates() -> AsyncStream<[LatencyUpdate]>

    // MARK: §6 规则
    func ruleStats() async -> RuleStats
    /// 域名或 IPv4/IPv6；O(len)。
    func testRule(input: String) async throws -> RuleTrace

    // MARK: §7 订阅与配置
    func subscriptions() -> AsyncStream<[Subscription]>
    func subscriptionsSummary() async -> SubscriptionsSummary
    /// file 时 payload = 文件内容。
    func importSubscription(source: ImportSource, payload: String) async throws -> Subscription
    func previewUpdate(id: String) async throws -> SubscriptionDiff
    func updateSubscription(id: String) async throws -> SubscriptionDiff
    func updateAll() async throws -> [SubscriptionDiff]
    func deleteSubscription(id: String) async throws

    // MARK: §8 连接、日志、设置
    /// 最多 200 条最新。
    func activeConnections() -> AsyncStream<[ConnectionInfo]>
    func closeConnection(id: String) async throws
    func closeAll() async throws
    func logs(minLevel: LogLevel) -> AsyncStream<LogLine>
    func settings() -> AsyncStream<Settings>
    /// 全量写回。
    func updateSettings(patch: Settings) async throws
    func storage() async -> StorageInfo

    // MARK: §9 命令搜索
    /// ≤ 8 条；空输入给"建议"。
    func commandSuggestions(input: String) async -> [CommandSuggestion]
}

// MARK: - 虚拟列表辅助（契约 §5 UI 约定）

public extension NodeQueryResult {
    /// 虚拟列表总行数 = total + sections.count（每个分区一行头）。
    var rowCount: Int64 { total + Int64(sections.count) }
}

/// 虚拟列表行号 → 分区头 / 节点序号。
public enum NodeListRow: Sendable, Hashable {
    /// 分区头：分区下标。
    case header(section: Int)
    /// 节点：分区下标、分区内序号、全局节点序号（nodeRows 的 offset）。
    case node(section: Int, indexInSection: Int64, ordinal: Int64)
}

public extension Array where Element == RegionSection {
    /// 行号 → (分区, 序号)，用 rowOffset 二分。row 越界返回 nil。
    func locate(row: Int64) -> NodeListRow? {
        guard !isEmpty, row >= 0 else { return nil }
        var lo = 0, hi = count - 1
        while lo < hi {
            let m = (lo + hi + 1) >> 1
            if self[m].rowOffset <= row { lo = m } else { hi = m - 1 }
        }
        let s = self[lo]
        let k = row - s.rowOffset
        if k == 0 { return .header(section: lo) }
        guard k - 1 < s.count else { return nil }
        // 节点序号 = rowOffset - 之前的头行数(lo) - 本头行(1) + k
        let ordinal = s.rowOffset - Int64(lo) + (k - 1)
        return .node(section: lo, indexInSection: k - 1, ordinal: ordinal)
    }
}

// MARK: - 契约 §13 / §14.z 新增方法的默认实现（Mock 未实现前不影响编译；CoreEngine 有真实实现）

public extension ZephyrEngine {
    /// 只读事件流：没有实现即没有事件（Mock / 预览不探测）。
    func sceneFailovers() -> AsyncStream<SceneFailoverNotice> { AsyncStream { $0.finish() } }
    // 默认抛“不支持”，不再静默成功（UI 会提示失败而不是假装生效，REVIEW-Q2 P2）。
    func setSceneSource(sceneId: String, source: SceneSource) async throws {
        throw ZephyrError(code: .internal, message: "setSceneSource unsupported")
    }
    func overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Bool) async throws {
        throw ZephyrError(code: .internal, message: "overrideHost unsupported")
    }
}

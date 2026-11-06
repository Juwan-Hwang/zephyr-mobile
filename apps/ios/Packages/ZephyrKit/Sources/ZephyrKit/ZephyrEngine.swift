// ZephyrEngine — iOS 侧的引擎协议。
//
// 这是 Swift 版契约；语言无关的权威版本由 A 维护在 contract/。两者不一致时以 contract/ 为准，
// iOS 跟进（在 #1 看板说明）。在 contract v0 发布前，本文件就是 iOS 的草案。
//
// 设计原则
//  - 规模：节点 1e7–1e8、规则 1e8。协议里绝不返回“全部节点/全部规则”，只返回计数 + 窗口（分页）。
//  - 线程：所有方法 async 且 Sendable，可在任意线程调用；实现方自己保证内部并发安全。
//  - 实时数据（流量、连接状态）走 AsyncStream，UI 侧按帧节流。
//  - 两个实现：MockEngine（ZephyrMock，按原型生成）与 CoreEngine（ZephyrCore，包装 UniFFI）。

import Foundation

public protocol ZephyrEngine: AnyObject, Sendable {

    // MARK: 连接
    /// 当前连接状态快照。
    func connectionState() async -> ConnectionState
    /// 连接状态变化流（立刻先推一次当前值）。
    func connectionStates() -> AsyncStream<ConnectionState>
    func connect() async throws
    func disconnect() async throws
    func setMode(_ mode: ProxyMode) async throws

    // MARK: 流量
    /// 实时速率，约 1 Hz。立刻先推一次。
    func trafficSamples() -> AsyncStream<TrafficSample>
    /// 最近 N 秒的速率历史（首页曲线冷启动用）。
    func trafficHistory(seconds: Int) async -> [TrafficSample]
    /// 今日用量汇总（首页“今日”、今日卡片、小组件）。
    func todayUsage() async -> DailyUsage

    // MARK: 场景与策略组
    func scenes() async -> [Scene]
    func sceneDetail(id: Scene.ID) async throws -> SceneDetail
    func selectNode(sceneID: Scene.ID, nodeID: NodeID) async throws
    func setSceneStrategy(sceneID: Scene.ID, strategy: SceneStrategy) async throws
    /// 重新检测场景池（只测场景候选，不做全量测速）。
    func retestScene(id: Scene.ID) async throws

    // MARK: 节点（索引 + 窗口）
    /// 节点库总览：总数、订阅数、地区分桶。
    func nodeLibrary() async -> NodeLibrarySummary
    /// 用查询构建一个结果集，返回句柄。查询走索引，绝不全表扫描。
    func queryNodes(_ query: NodeQuery) async throws -> NodeResultSet
    /// 读结果集的一个窗口：[range.lowerBound, range.upperBound) 行（行 = 地区头 或 节点）。
    func rows(in set: NodeResultSet, range: Range<Int>) async throws -> [NodeListRow]
    /// 只返回缓存的延迟；没有缓存就是 nil。
    func cachedLatency(_ ids: [NodeID]) async -> [NodeID: Latency]
    /// 按需测速（可见行停止滚动 400ms 后调用）。结果逐个推回。
    func testLatency(_ ids: [NodeID]) -> AsyncStream<(NodeID, Latency)>

    // MARK: 规则
    func ruleLibrary() async -> RuleLibrarySummary
    /// 规则测试：域名或 IP → 命中链（层 → 规则 → 场景 → 出口）。
    func testRule(_ input: String) async throws -> RuleTrace

    // MARK: 订阅
    func subscriptions() async -> SubscriptionSummary
    func importSubscription(_ source: ImportSource) async throws -> Subscription
    func updateSubscription(id: Subscription.ID) async throws -> SubscriptionDiff
    func removeSubscription(id: Subscription.ID) async throws

    // MARK: 连接记录
    func recentConnections(limit: Int) async -> [ConnectionRecord]
    func connectionTrace(id: ConnectionRecord.ID) async throws -> ConnectionTrace
    func setOverride(for host: String, target: ConnectionOverride, always: Bool) async throws

    // MARK: 指令（搜索栏里的自然语言指令）
    func parseCommand(_ text: String) async -> CommandPlan?
    func apply(_ plan: CommandPlan) async throws

    // MARK: 设置
    func settings() async -> EngineSettings
    func update(_ settings: EngineSettings) async throws
    func storageUsage() async -> StorageUsage
}

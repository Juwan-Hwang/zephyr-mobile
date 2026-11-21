// 契约 §15.h 指令层测试用引擎：其余全部委托 MockEngine（冻结时钟），只替换场景节点过滤两条接口；
// 另记录 overrideHost 调用（§16.d 直连测试）。
// Mock 的视频池没有名字含 4K 的节点（set 必抛错），无法覆盖“开启成功 / 撤销 / 已开启可取消”，故用可配置的预览结果。
// 过滤状态叠加在 scenes() 上推送；set 时借 base.setSceneNodeFilter(nil) 触发一次场景重发。

import Foundation
import ZephyrKit
import ZephyrMock

final class FilterStubEngine: ZephyrEngine, @unchecked Sendable {
    let base: MockEngine
    private let lock = NSLock()
    private var _preview: NodeFilterPreview
    private var _filters: [String: SceneNodeFilter] = [:]
    private var _setCalls: [SceneNodeFilter?] = []
    private var _overrides: [HostOverrideCall] = []

    /// overrideHost 的调用记录（契约 §16.d “GitHub 直连”测试用；Mock 本身只写日志）。
    struct HostOverrideCall: Equatable {
        var host: String
        var target: TraceTarget
        var sceneId: String?
        var persistent: Bool
    }

    init(preview: NodeFilterPreview, active: [String: SceneNodeFilter] = [:]) {
        base = MockEngine(seed: 0, clock: .frozen941, startConnected: true)
        _preview = preview
        _filters = active
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var preview: NodeFilterPreview {
        get { locked { _preview } }
        set { locked { _preview = newValue } }
    }
    /// setSceneNodeFilter 的调用记录（被拒绝的调用不记录）。
    var setCalls: [SceneNodeFilter?] { locked { _setCalls } }
    var overrideCalls: [HostOverrideCall] { locked { _overrides } }

    private func overlay(_ list: [ZephyrKit.Scene]) -> [ZephyrKit.Scene] {
        let f = locked { _filters }
        return list.map { s in var s = s; s.nodeFilter = f[s.id]; return s }
    }

    // MARK: §15.h（替换）

    func previewSceneNodeFilter(sceneId: String, filter: SceneNodeFilter) async throws -> NodeFilterPreview {
        _ = try await base.sceneCandidates(sceneId: sceneId, region: nil)   // 未知场景同样抛 sceneNotFound
        return preview
    }

    func setSceneNodeFilter(sceneId: String, filter: SceneNodeFilter?) async throws {
        if filter != nil, preview.poolMatching == 0 {
            throw ZephyrError(code: .ruleInputInvalid, message: "no node matches")
        }
        locked { _filters[sceneId] = filter; _setCalls.append(filter) }
        try await base.setSceneNodeFilter(sceneId: sceneId, filter: nil)   // 只为重发 scenes()
    }

    func scenes() -> AsyncStream<[ZephyrKit.Scene]> {
        let src = base.scenes()
        return AsyncStream { cont in
            let task = Task { [weak self] in
                for await list in src {
                    guard let self else { break }
                    cont.yield(self.overlay(list))
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 其余委托 MockEngine

    func connectionState() -> AsyncStream<ConnectionState> { base.connectionState() }
    func connect() async throws { try await base.connect() }
    func disconnect() async throws { try await base.disconnect() }
    func setMode(mode: ProxyMode) async throws { try await base.setMode(mode: mode) }
    func setGlobalNode(id: NodeId) async throws -> ExitChange { try await base.setGlobalNode(id: id) }
    func traffic() -> AsyncStream<TrafficSample> { base.traffic() }
    func recentTraffic(seconds: Int32) -> [TrafficSample] { base.recentTraffic(seconds: seconds) }
    func usageToday() async -> UsageSummary { await base.usageToday() }
    func sceneFailovers() -> AsyncStream<SceneFailoverNotice> { base.sceneFailovers() }
    func sceneCandidates(sceneId: String, region: String?) async throws -> [NodeSummary] {
        try await base.sceneCandidates(sceneId: sceneId, region: region)
    }
    func nodeFunnel(maxAgeMs: Int64, thresholdMs: Int32) async -> NodeFunnel? {
        await base.nodeFunnel(maxAgeMs: maxAgeMs, thresholdMs: thresholdMs)
    }
    func sceneFunnel(sceneId: String, maxAgeMs: Int64, thresholdMs: Int32) async -> NodeFunnel? {
        await base.sceneFunnel(sceneId: sceneId, maxAgeMs: maxAgeMs, thresholdMs: thresholdMs)
    }
    func previewSceneChange(sceneId: String, nodeId: NodeId) async throws -> ExitChange {
        try await base.previewSceneChange(sceneId: sceneId, nodeId: nodeId)
    }
    func applySceneChange(sceneId: String, nodeId: NodeId) async throws {
        try await base.applySceneChange(sceneId: sceneId, nodeId: nodeId)
    }
    func retestScene(sceneId: String) async throws -> ZephyrKit.Scene { try await base.retestScene(sceneId: sceneId) }
    func setSceneSource(sceneId: String, source: SceneSource) async throws {
        try await base.setSceneSource(sceneId: sceneId, source: source)
    }
    func overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Bool) async throws {
        try await base.overrideHost(host: host, target: target, sceneId: sceneId, persistent: persistent)
        locked { _overrides.append(HostOverrideCall(host: host, target: target, sceneId: sceneId, persistent: persistent)) }
    }
    func setSceneException(sceneId: String, appId: String, nodeId: NodeId?) async throws {
        try await base.setSceneException(sceneId: sceneId, appId: appId, nodeId: nodeId)
    }
    func policyGroups() -> AsyncStream<[PolicyGroup]> { base.policyGroups() }
    func groupMembers(group: String, offset: Int32, limit: Int32) async throws -> NodePage {
        try await base.groupMembers(group: group, offset: offset, limit: limit)
    }
    func selectInGroup(group: String, nodeId: NodeId) async throws { try await base.selectInGroup(group: group, nodeId: nodeId) }
    func testGroup(group: String) async throws { try await base.testGroup(group: group) }
    func nodeIndex() async -> NodeIndex { await base.nodeIndex() }
    func queryNodes(query: String) async throws -> NodeQueryResult { try await base.queryNodes(query: query) }
    func nodeRows(token: Int64, offset: Int64, limit: Int32) async throws -> NodePage {
        try await base.nodeRows(token: token, offset: offset, limit: limit)
    }
    func node(id: NodeId) async throws -> NodeDetail { try await base.node(id: id) }
    func testLatency(ids: [NodeId]) async { await base.testLatency(ids: ids) }
    func latencyUpdates() -> AsyncStream<[LatencyUpdate]> { base.latencyUpdates() }
    func scanLatency(query: String) -> AsyncStream<ScanProgress> { base.scanLatency(query: query) }
    func ruleStats() async -> RuleStats { await base.ruleStats() }
    func testRule(input: String) async throws -> RuleTrace { try await base.testRule(input: input) }
    func subscriptions() -> AsyncStream<[Subscription]> { base.subscriptions() }
    func subscriptionsSummary() async -> SubscriptionsSummary { await base.subscriptionsSummary() }
    func importSubscription(source: ImportSource, payload: String) async throws -> Subscription {
        try await base.importSubscription(source: source, payload: payload)
    }
    func previewUpdate(id: String) async throws -> SubscriptionDiff { try await base.previewUpdate(id: id) }
    func updateSubscription(id: String) async throws -> SubscriptionDiff { try await base.updateSubscription(id: id) }
    func updateAll() async throws -> [SubscriptionDiff] { try await base.updateAll() }
    func deleteSubscription(id: String) async throws { try await base.deleteSubscription(id: id) }
    func activeConnections() -> AsyncStream<[ConnectionInfo]> { base.activeConnections() }
    func hostTrace(host: String) async -> HostTraceInfo? { await base.hostTrace(host: host) }
    func hostOverride(host: String) async -> HostOverrideInfo? { await base.hostOverride(host: host) }
    func closeConnection(id: String) async throws { try await base.closeConnection(id: id) }
    func closeAll() async throws { try await base.closeAll() }
    func logs(minLevel: LogLevel) -> AsyncStream<LogLine> { base.logs(minLevel: minLevel) }
    func settings() -> AsyncStream<Settings> { base.settings() }
    func updateSettings(patch: Settings) async throws { try await base.updateSettings(patch: patch) }
    func storage() async -> StorageInfo { await base.storage() }
    func localProxyCredential() async -> String { await base.localProxyCredential() }
    func resetLocalProxyCredential() async -> String { await base.resetLocalProxyCredential() }
    func commandSuggestions(input: String) async -> [CommandSuggestion] { await base.commandSuggestions(input: input) }
}

// LibraryModel — 资料库 sheet 的数据：4 个统计数字（节点 / 订阅 / 规则 / 场景）+ 设置摘要（受信任 Wi‑Fi、本地端口）。
// 数字一律来自引擎：nodeIndex().total、subscriptions 流、ruleStats().total、scenes 流。

import Foundation
import Observation
import ZephyrKit

@MainActor
@Observable
final class LibraryModel {
    @ObservationIgnored let engine: any ZephyrEngine

    private(set) var nodeTotal: Int64?
    private(set) var subscriptionCount: Int64?
    private(set) var ruleTotal: Int64?
    private(set) var sceneCount: Int64?
    private(set) var settings: Settings?

    init(engine: any ZephyrEngine) { self.engine = engine }

    /// 在 `.task` 里调用；视图消失时随 task 取消。
    func start() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCounts() }
            group.addTask { await self.observeSubscriptions() }
            group.addTask { await self.observeScenes() }
            group.addTask { await self.observeSettings() }
        }
    }

    private func loadCounts() async {
        async let index = engine.nodeIndex()
        async let rules = engine.ruleStats()
        let (i, r) = await (index, rules)
        nodeTotal = i.total
        ruleTotal = r.total
    }

    private func observeSubscriptions() async {
        for await subs in engine.subscriptions() { subscriptionCount = Int64(subs.count) }
    }

    private func observeScenes() async {
        for await scenes in engine.scenes() { sceneCount = Int64(scenes.count) }
    }

    private func observeSettings() async {
        for await s in engine.settings() { settings = s }
    }

    // MARK: 派生文案

    /// 中文紧凑格式：13,109,802 → "1,311 万"；214 → "214"；103,606,731 → "1.04 亿"。
    nonisolated static func compact(_ n: Int64?) -> String? { n.map(CompactCount.zh) }

    /// 受信任 Wi‑Fi 行的值：“家” / “家 等 3 个” / “无” / “关”。
    var trustedWifiText: String? {
        guard let s = settings else { return nil }
        return Self.trustedWifiText(s)
    }

    /// 本地代理端口行的值：关闭时“关”（原型 lib.png），开启时显示端口“7890”（契约 §14.z localProxyEnabled）。
    var localPortText: String? { settings.map(Self.localProxyText) }

    nonisolated static func localProxyText(_ s: Settings) -> String {
        s.localProxyEnabled ? String(s.localProxyPort) : "关"
    }

    nonisolated static func trustedWifiText(_ s: Settings) -> String {
        guard s.disconnectOnTrusted else { return "关" }
        guard let first = s.trustedWifi.first else { return "无" }
        return s.trustedWifi.count == 1 ? first : "\(first) 等 \(s.trustedWifi.count) 个"
    }
}

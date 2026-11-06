// 快照用的确定性数据：原型 9:41 冻结时钟、MockEngine 工厂、小组件 SharedState 变体。

import Foundation
import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

enum SnapshotFixtures {
    /// 原型的“现在”：2026-11-06 09:41:00 +08:00（MockClock.frozen941）。
    static let now = Date(timeIntervalSince1970: TimeInterval(MockClock.prototypeMillis) / 1000)

    /// 冻结时钟的 MockEngine；accent 非 blue 时写进引擎设置（NodesView / RulesView / RootView 从引擎读强调色）。
    static func engine(connected: Bool = true, accent: ZTokens.Accent = .blue) async -> MockEngine {
        let engine = MockEngine(seed: 0, clock: .frozen941, startConnected: connected)
        await apply(accent: accent, to: engine)
        return engine
    }

    /// 把强调色写进引擎设置（读当前设置 → 改 accent → updateSettings）。
    static func apply(accent: ZTokens.Accent, to engine: any ZephyrEngine) async {
        guard accent != .blue, let value = ZephyrKit.Accent(rawValue: accent.rawValue) else { return }
        var current: ZephyrKit.Settings?
        for await s in engine.settings() { current = s; break }
        guard var patch = current else { return }
        patch.accent = value
        try? await engine.updateSettings(patch: patch)
    }

    // MARK: 小组件 / 实时活动

    static var connected: SharedState { SharedState.prototype(now: now) }

    static func accent(_ accent: ZTokens.Accent) -> SharedState {
        var s = connected
        s.accent = accent.rawValue
        return s
    }

    static var disconnected: SharedState {
        var s = connected
        s.connection = .init(status: .disconnected, mode: .rule, since: nil, errorCode: nil)
        s.rate = .init(downBps: 0, upBps: 0, at: nil, recentDown: [])
        return s
    }

    static var failed: SharedState {
        var s = disconnected
        s.connection.status = .failed
        s.connection.errorCode = "network_unavailable"
        return s
    }

    static var global: SharedState {
        var s = connected
        s.connection.mode = .global
        return s
    }

    /// 首次安装：无订阅、无用量。
    static var empty: SharedState {
        var s = SharedState.empty
        s.updatedAt = now
        s.usage = .init(day: Calendar.current.startOfDay(for: now), todayBytes: 0,
                        hourly: Array(repeating: 0, count: 24), regionsToday: 0, fastestLatencyMs: nil)
        return s
    }

    /// 场景含超时 / 未测 / 超长节点名。
    static var edgyScenes: SharedState {
        var s = connected
        s.scenes = [
            .init(id: "ai", name: "AI", region: "JP", nodeName: "东京 03 · IPLC 专线 · 超长节点名称测试", latencyMs: 61),
            .init(id: "video", name: "视频", region: "HK", nodeName: "香港 HKT", latencyMs: -1),
            .init(id: "other", name: "其他", region: "TW", nodeName: "TW-Fixed-01", latencyMs: nil),
        ]
        return s
    }

    static var activity: ZephyrActivityAttributes.ContentState { .prototype(now: now) }
}

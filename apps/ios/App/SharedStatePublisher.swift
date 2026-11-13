// SharedStatePublisher —— 引擎实时流 → SharedState（App Group）→ 小组件 / 控制中心 / 实时活动。
//
// 写盘节流：连接状态 / 模式 / 场景 / 强调色变化立即写并 reload 小组件；速率每 5 秒最多写一次（不 reload，
// 小组件按 15 分钟时间线自然刷新，避免耗尽 WidgetKit 的刷新预算）。今日用量每分钟取一次。

import Foundation
import WidgetKit
import ZephyrKit

@MainActor
final class SharedStatePublisher {
    static let rateWriteInterval: TimeInterval = 5
    static let usagePollInterval: Duration = .seconds(60)

    /// (新状态, 是否“显著变化”)。LiveActivityController 订阅。
    var onChange: ((SharedState, Bool) -> Void)?

    private let engine: any ZephyrEngine
    private let store: SharedStore
    private(set) var state: SharedState
    private var tasks: [Task<Void, Never>] = []
    private var lastWrite = Date.distantPast
    private var pendingWrite: Task<Void, Never>?
    private var dirty: SharedState.Fields = []

    init(engine: any ZephyrEngine, store: SharedStore = .shared) {
        self.engine = engine
        self.store = store
        self.state = store.read()
    }

    func start() {
        guard tasks.isEmpty else { return }
        let engine = self.engine
        tasks = [
            Task { [weak self] in
                for await value in engine.connectionState() { self?.apply(connection: value) }
            },
            Task { [weak self] in
                for await value in engine.traffic() { self?.apply(traffic: value) }
            },
            Task { [weak self] in
                for await value in engine.scenes() { self?.apply(scenes: value) }
            },
            Task { [weak self] in
                for await value in engine.settings() { self?.apply(settings: value) }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    let usage = await engine.usageToday()
                    self?.apply(usage: usage)
                    try? await Task.sleep(for: Self.usagePollInterval)
                }
            },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        pendingWrite?.cancel()
    }

    // MARK: 映射（ZephyrKit 契约类型 → SharedState 基础类型）

    func apply(connection value: ConnectionState) {
        let status = SharedState.Status(rawValue: value.status.rawValue) ?? .disconnected
        let mode = SharedState.Mode(rawValue: value.mode.rawValue) ?? .rule
        let significant = status != state.connection.status || mode != state.connection.mode
        state.connection = SharedState.Connection(
            status: status,
            mode: mode,
            since: value.since.map(Self.date(fromMillis:)),
            errorCode: value.error?.code.rawValue
        )
        state.tunnel.mode = mode
        if status != .connected {
            state.rate.downBps = 0
            state.rate.upBps = 0
            state.rate.at = Date()   // 归零也要比扩展最后一次写入新，合并时才能生效
        }
        commit([.connection, .rate], significant: significant)
    }

    func apply(traffic value: TrafficSample) {
        state.rate.push(down: value.downBps, up: value.upBps, at: Self.date(fromMillis: value.at))
        commit(.rate, significant: false)
    }

    func apply(scenes value: [Scene]) {
        let summaries = value.prefix(4).map { scene in
            SharedState.SceneSummary(
                id: scene.id,
                name: scene.name,
                region: scene.selected.region,
                nodeName: scene.selected.name,
                latencyMs: scene.selected.latencyMs.map { Int($0) }
            )
        }
        // 延迟数值变化不算显著（REVIEW-Q2 X-P1-15），见 SharedState.scenesShape。
        let significant = SharedState.scenesShape(Array(summaries)) != SharedState.scenesShape(state.scenes)
        state.scenes = Array(summaries)
        commit(.scenes, significant: significant)
    }

    func apply(settings value: Settings) {
        let accent = value.accent.rawValue
        let significant = accent != state.accent
        state.accent = accent
        state.tunnel.mtu = Int(value.tun.mtu)
        state.tunnel.ipv6 = value.tun.ipv6
        commit(.appearance, significant: significant)
    }

    func apply(usage value: UsageSummary) {
        let now = Date()
        state.usage = SharedState.Usage(
            day: Calendar.current.startOfDay(for: now),
            todayBytes: value.todayBytes,
            hourly: value.hourly,
            regionsToday: Int(value.regionsToday),
            fastestLatencyMs: value.fastestLatencyMs.map { Int($0) }
        )
        commit(.usage, significant: false)
    }

    // MARK: 写盘 / 刷新

    private func commit(_ changed: SharedState.Fields, significant: Bool) {
        dirty.formUnion(changed)
        onChange?(state, significant)
        let now = Date()
        if significant || now.timeIntervalSince(lastWrite) >= Self.rateWriteInterval {
            write(reloadWidgets: significant)
            return
        }
        guard pendingWrite == nil else { return }
        let delay = Self.rateWriteInterval - now.timeIntervalSince(lastWrite)
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, delay)))
            guard !Task.isCancelled else { return }
            self?.pendingWrite = nil
            self?.write(reloadWidgets: false)
        }
    }

    private func write(reloadWidgets: Bool) {
        pendingWrite?.cancel()
        pendingWrite = nil
        lastWrite = Date()
        let snapshot = state, fields = dirty
        dirty = []
        do {
            let merged = try store.update { $0.adopt(appSnapshot: snapshot, fields: fields) }
            // 盘上可能有扩展写的更新速率：内存跟上，实时活动 / onChange 不显示旧值
            if merged.rate != state.rate {
                state.rate = merged.rate
                onChange?(state, false)
            }
        } catch {
            dirty.formUnion(fields)
            return
        }
        guard reloadWidgets else { return }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: WidgetKinds.connectionControl)
        }
    }

    nonisolated static func date(fromMillis ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}

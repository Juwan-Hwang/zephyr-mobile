// AppModel 的实时流订阅与生命周期。
//
//  connectionState / scenes / subscriptions：App 存活期间一直订阅（低频）。
//  traffic：仅在"前台 且 已连接"时订阅；进后台立即取消（省电），回前台先用 recentTraffic 回填 300 点再续订。

import Foundation
import SwiftUI
import ZephyrKit

extension AppModel {

    /// 开始订阅。重复调用无副作用。
    public func start() {
        guard !started else { return }
        started = true
        let engine = self.engine

        streamTasks.append(Task { [weak self] in
            for await state in engine.connectionState() {
                guard let self else { return }
                self.apply(connection: state)
            }
        })
        streamTasks.append(Task { [weak self] in
            for await list in engine.scenes() {
                guard let self else { return }
                self.scenes = list
            }
        })
        streamTasks.append(Task { [weak self] in
            for await list in engine.subscriptions() {
                guard let self else { return }
                self.subscriptions = list
                self.subscriptionsLoaded = true
            }
        })
        streamTasks.append(Task { [weak self] in
            for await s in engine.settings() {
                guard let self else { return }
                self.settings = s
            }
        })
        Task { await refreshUsage() }
    }

    /// 停止全部订阅（测试 / 切换引擎时用）。
    public func stop() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        trafficTask?.cancel()
        trafficTask = nil
        started = false
    }

    /// 由 RootView 的 `.onChange(of: scenePhase)` 调用。
    public func scenePhaseChanged(_ phase: ScenePhase) {
        // .inactive（下拉通知中心、控制中心、App 切换器、来电）仍可见，不能当作后台去切断流量流（REVIEW-Q2 X-P1-16）。
        let fg = phase != .background
        guard fg != isForeground else { return }
        isForeground = fg
        reconcileTraffic()
        if fg { Task { await refreshUsage() } }
    }

    public func refreshUsage() async {
        usage = await engine.usageToday()
    }

    // MARK: 内部

    func apply(connection new: ConnectionState) {
        let old = connection
        connection = new
        if old.globalNodeId != new.globalNodeId { resolveGlobalNode(new.globalNodeId) }
        if old.status != new.status {
            if new.status == .disconnected { traffic.clear(); pendingChange = nil }
            reconcileTraffic()
        }
    }

    /// 前台且已连接 → 订阅流量；否则取消。
    func reconcileTraffic() {
        let want = isForeground && connection.status == .connected
        if want, trafficTask == nil {
            let engine = self.engine
            let capacity = Int32(TrafficStore.capacity)
            trafficTask = Task { [weak self] in
                // 真实引擎的 recentTraffic 走 FFI / 锁，不在主线程做（REVIEW-Q1 H-P2-19）。
                let history = await Task.detached(priority: .userInitiated) {
                    engine.recentTraffic(seconds: capacity)
                }.value
                if Task.isCancelled { return }
                self?.traffic.backfill(history)
                for await s in engine.traffic() {
                    guard let self, !Task.isCancelled else { return }
                    self.traffic.push(s)
                }
                // 流自然结束（引擎断开）：允许下次重新订阅；被取消时 trafficTask 已由取消方清空。
                if !Task.isCancelled { self?.trafficTask = nil }
            }
        } else if !want, let t = trafficTask {
            t.cancel()
            trafficTask = nil
        }
    }

    func resolveGlobalNode(_ id: NodeId?) {
        guard let id else { globalNode = nil; return }
        // 先从场景里找（免一次往返），找不到再问引擎。
        if let hit = scenes.map(\.selected).first(where: { $0.id == id }) { globalNode = hit; return }
        Task { [weak self] in
            guard let self else { return }
            if let d = try? await self.engine.node(id: id), self.connection.globalNodeId == id {
                self.globalNode = d.summary
            }
        }
    }
}

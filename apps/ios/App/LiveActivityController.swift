// LiveActivityController —— 连接期间维持一个实时活动（锁屏卡片 + 灵动岛）。
//
//  connected            → 无活动则 request；有则按需 update（显著变化立即，速率变化 ≥ 5 秒且变动 ≥ 5%）
//  disconnected/failed  → end（立即移除）
// 冷启动时接管上次残留的活动。staleDate 2 分钟：App 被挂起后系统把卡片标成过期，而不是显示假的实时速率。
// Release 真机上 App 在后台时由 PacketTunnel 继续运行，但扩展不能更新实时活动（需推送）；见 NOTES-X。

import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityController {
    static let staleAfter: TimeInterval = 120

    private var activity: Activity<ZephyrActivityAttributes>?
    private var lastContent: ZephyrActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private let log = Logger(subsystem: "app.zephyr.mobile", category: "live-activity")

    init() {
        activity = Activity<ZephyrActivityAttributes>.activities.first
    }

    func sync(_ state: SharedState, significant: Bool) {
        let content = ZephyrActivityAttributes.ContentState(state)
        let active = activity.map { $0.activityState == .active } ?? false
        switch LiveActivityPolicy.action(status: state.connection.status, significant: significant, hasActiveActivity: active,
                                         content: content, last: lastContent, lastUpdate: lastUpdate, now: Date()) {
        case .start: start(content, accent: state.accent)
        case .update: if let activity { update(activity, content) }
        case .end: end()
        case .keep: break
        }
    }

    private func start(_ content: ZephyrActivityAttributes.ContentState, accent: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        do {
            activity = try Activity.request(
                attributes: ZephyrActivityAttributes(startedAt: now, accent: accent),
                content: ActivityContent(state: content, staleDate: now.addingTimeInterval(Self.staleAfter)),
                pushType: nil
            )
            lastContent = content
            lastUpdate = now
        } catch {
            log.error("request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(_ activity: Activity<ZephyrActivityAttributes>, _ content: ZephyrActivityAttributes.ContentState) {
        let now = Date()
        lastContent = content
        lastUpdate = now
        Task {
            await activity.update(ActivityContent(state: content, staleDate: now.addingTimeInterval(Self.staleAfter)))
        }
    }

    private func end() {
        let all = Activity<ZephyrActivityAttributes>.activities
        activity = nil
        lastContent = nil
        guard !all.isEmpty else { return }
        Task {
            for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

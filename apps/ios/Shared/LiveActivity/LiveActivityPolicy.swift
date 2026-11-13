// 实时活动的决策规则（纯函数，单测见 Shared/Tests/LiveActivityPolicyTests.swift，REVIEW-Q2 X-P1-8）。
// LiveActivityController 只负责调用 ActivityKit。

import Foundation

enum LiveActivityPolicy {
    static let minUpdateInterval: TimeInterval = 5
    /// 速率相对上次变化达到这个比例才值得刷新（显著变化不受限）。
    static let rateChangeThreshold = 0.05

    enum Action: Equatable {
        case start
        case update
        case end
        case keep
    }

    /// - Parameters:
    ///   - hasActiveActivity: 当前有处于 active 的实时活动
    ///   - last: 上次推给活动的内容（nil = 还没推过）
    static func action(status: SharedState.Status, significant: Bool, hasActiveActivity: Bool,
                       content: ZephyrActivityAttributes.ContentState,
                       last: ZephyrActivityAttributes.ContentState?, lastUpdate: Date, now: Date) -> Action {
        switch status {
        case .connected:
            guard hasActiveActivity else { return .start }
            return significant || shouldUpdate(to: content, last: last, lastUpdate: lastUpdate, now: now) ? .update : .keep
        case .disconnected, .failed:
            return .end
        case .connecting, .disconnecting:
            return .keep
        }
    }

    static func shouldUpdate(to content: ZephyrActivityAttributes.ContentState,
                             last: ZephyrActivityAttributes.ContentState?, lastUpdate: Date, now: Date) -> Bool {
        guard now.timeIntervalSince(lastUpdate) >= minUpdateInterval else { return false }
        guard let last else { return true }
        if last.scenes != content.scenes || last.mode != content.mode || last.status != content.status { return true }
        let base = max(Double(last.downBps), 1)
        return abs(Double(content.downBps) - Double(last.downBps)) / base >= rateChangeThreshold
    }
}

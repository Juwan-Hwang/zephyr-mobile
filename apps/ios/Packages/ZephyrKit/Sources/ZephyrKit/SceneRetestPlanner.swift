// SceneRetestPlanner —— 哪些场景的检测结果已过期（REVIEW-Q2 X-P1-5：“结果保留”设置与“每天检测”此前没有执行方）。
// 纯函数，Linux 可测。App 在回到前台 / 后台刷新时调用，隧道在跑时才有意义（探测必须经 VPN）。

import Foundation

public enum SceneRetestPlanner {
    /// 同一场景两次自动重测之间至少间隔（毫秒）：失败时 `testedAt` 不变，避免每次前台都重试。
    public static let minRetryMillis: Int64 = 30 * 60 * 1000
    /// 设置里没有 TTL 时的兜底（小时，与契约默认设置一致）。
    public static let fallbackTtlHours: Int32 = 24

    /// 需要重测的场景 id（按场景顺序）。
    /// - `connected`：隧道没连上就不测（只会返回缓存）。
    /// - 从没测过（`testedAt == nil`）或距今 ≥ `latencyTtlHours` 小时即过期。
    /// - 没有可用节点的场景也要测（也许恢复了）；`lastAttempt` 用于退避。
    public static func due(_ scenes: [Scene], settings: Settings?, connected: Bool, now: Int64,
                           lastAttempt: [String: Int64] = [:]) -> [String] {
        guard connected else { return [] }
        let ttlHours = (settings?.latencyTtlHours ?? 0) > 0 ? settings!.latencyTtlHours : fallbackTtlHours
        let ttl = Int64(ttlHours) * 3_600_000
        return scenes.compactMap { scene in
            if let last = lastAttempt[scene.id], now - last < minRetryMillis { return nil }
            guard let tested = scene.testedAt else { return scene.id }
            return now - tested >= ttl ? scene.id : nil
        }
    }
}

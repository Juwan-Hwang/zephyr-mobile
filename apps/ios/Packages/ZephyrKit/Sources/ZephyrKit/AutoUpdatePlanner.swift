// AutoUpdatePlanner —— 哪些订阅到了自动更新时间（REVIEW-Q2 X-P1-5：此前设置里的“自动更新”没有任何执行方）。
// 纯函数，Linux 可测。App 的后台刷新任务与回到前台时调用。

import Foundation

public enum AutoUpdatePlanner {
    /// 没有任何配置时的兜底间隔（与契约默认设置一致）。
    public static let fallbackHours: Int32 = 12
    /// 同一订阅两次自动尝试之间至少间隔（毫秒）：更新失败时 `updatedAt` 不变，避免每次前台都重试。
    public static let minRetryMillis: Int64 = 15 * 60 * 1000

    /// 到期需要更新的订阅 id（按订阅顺序）。
    /// - 只更新有远程地址的订阅（本地导入的没有）。
    /// - 间隔取订阅自己的 `autoUpdateHours`，≤ 0 时用设置里的，再没有用 12 小时。
    /// - `lastAttempt`：id → 上次自动尝试的毫秒时间戳（失败也记），用于退避。
    public static func due(_ subs: [Subscription], settings: Settings?, now: Int64,
                           lastAttempt: [String: Int64] = [:]) -> [String] {
        subs.compactMap { sub in
            guard let url = sub.url, !url.isEmpty else { return nil }
            if let last = lastAttempt[sub.id], now - last < minRetryMillis { return nil }
            let hours = sub.autoUpdateHours > 0 ? sub.autoUpdateHours
                : ((settings?.autoUpdateHours ?? 0) > 0 ? settings!.autoUpdateHours : fallbackHours)
            guard let updated = sub.updatedAt else { return sub.id }
            return now - updated >= Int64(hours) * 3_600_000 ? sub.id : nil
        }
    }
}

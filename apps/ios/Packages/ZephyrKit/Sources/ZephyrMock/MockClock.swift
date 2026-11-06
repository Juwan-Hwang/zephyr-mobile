// MockClock：.live 跟随系统时间；.frozen941 固定在原型的 2026-11-06 9:41（Asia/Shanghai，UTC+8），快照用。

import Foundation
import ZephyrKit

public struct MockClock: Sendable, Hashable {
    /// nil = 跟随系统时间。
    public let fixedMillis: Int64?
    /// 是否真的等待（连接 600ms、测速 80–400ms、1 Hz 流量）。冻结时钟下一律立即完成，快照/测试稳定。
    public let realDelays: Bool

    public init(fixedMillis: Int64?, realDelays: Bool) {
        self.fixedMillis = fixedMillis; self.realDelays = realDelays
    }

    public static let live = MockClock(fixedMillis: nil, realDelays: true)

    /// 2026-11-06 09:41:00 +08:00
    public static let prototypeMillis: Int64 = 1_793_929_260_000
    /// 原型首页连接时长 2:14:07。
    public static let prototypeConnectedMillis: Int64 = (2 * 3600 + 14 * 60 + 7) * 1000

    public static let frozen941 = MockClock(fixedMillis: prototypeMillis, realDelays: false)

    /// 冻结在任意时刻（测试用）。
    public static func frozen(at millis: Int64, realDelays: Bool = false) -> MockClock {
        MockClock(fixedMillis: millis, realDelays: realDelays)
    }

    public var isFrozen: Bool { fixedMillis != nil }

    public func now() -> Int64 { fixedMillis ?? ZFormat.nowMillis() }

    func sleep(ms: Int64) async {
        guard realDelays, ms > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
}

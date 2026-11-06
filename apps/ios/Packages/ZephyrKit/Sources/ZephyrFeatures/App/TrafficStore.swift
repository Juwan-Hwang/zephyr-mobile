// 高频流量数据单独放一个 @Observable 对象：只有读它的小视图（速率数字、曲线）会随 1 Hz 样本重算，
// 首页 body 只持有引用、不读取属性，因此不会被流量刷新拖着整页重算。

import Foundation
import Observation
import ZephyrKit

@MainActor
@Observable
public final class TrafficStore {
    /// 300 点环形缓冲（≈ 5 分钟 @1 Hz）。
    public private(set) var ring = RateRing(capacity: TrafficStore.capacity)
    /// 最新样本（速率大数字）。未连接 / 无数据时为 nil。
    public private(set) var latest: RatePoint?
    /// 最新样本到达的本地单调时间（秒），曲线据此做 60fps 平滑滚动插值。
    @ObservationIgnored public private(set) var latestArrival: TimeInterval = 0

    public nonisolated static let capacity = 300

    public init() {}

    func backfill(_ samples: [TrafficSample]) {
        ring.removeAll()
        ring.append(contentsOf: samples.suffix(Self.capacity).map(RatePoint.init))
        latest = ring.last
        latestArrival = ProcessInfo.processInfo.systemUptime
    }

    func push(_ s: TrafficSample) {
        let p = RatePoint(s)
        // 引擎重连时可能重复推送同一秒，按时间戳去重。
        if let last = ring.last, last.at >= p.at { return }
        ring.append(p)
        latest = p
        latestArrival = ProcessInfo.processInfo.systemUptime
    }

    func clear() {
        ring.removeAll()
        latest = nil
    }
}

extension RatePoint {
    init(_ s: TrafficSample) { self.init(at: s.at, down: s.downBps, up: s.upBps) }
}

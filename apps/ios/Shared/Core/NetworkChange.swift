// NetworkChange —— “默认底层网络变了”的判定与 2 s 去抖（契约 §16.a③ E04）。纯值，不依赖 Network 框架，便于单测。
//
// PacketTunnel 用 NWPathMonitor（排除 utun 的 .other 接口）把每次路径更新折成 `NetworkFingerprint` 交给 `NetworkChangeDetector`：
//   - 算“变了”：Wi‑Fi ↔ 蜂窝、换了接口、换了网关（换 SSID 时网关通常随之变化；NWPath 不暴露 SSID）；
//   - 不算：首个快照（基线）、网络暂时不可用（Wi‑Fi A → 无 → Wi‑Fi A 是同一网络上的短暂重连）、
//     隧道 reasserting 期间、仅 isExpensive / isConstrained 之类属性抖动。
// 判定为变化后由 `Debouncer` 合并 2 s 内的连续变化，到点执行一次：closeAll（扩展）+ Darwin 通知 `.networkChanged`
//（App 在前台且已连接时据此立即跑下一轮场景故障探测）。不重载配置、不重建 TUN。
// 受信任 Wi‑Fi 的重新评估由系统按需规则在网络变化时自行完成（OnDemandRules）。

import Foundation

struct NetworkFingerprint: Equatable, Sendable {
    /// 路径可用（NWPath.status == .satisfied）。
    var satisfied: Bool
    /// 首选的物理接口，"wifi:en0" / "cellular:pdp_ip0" / "wiredEthernet:en2"；没有为 nil。
    var primaryInterface: String?
    /// 网关地址（排序后），用于区分同一接口上换了网络。
    var gateways: [String]

    init(satisfied: Bool, primaryInterface: String?, gateways: [String]) {
        self.satisfied = satisfied
        self.primaryInterface = primaryInterface
        self.gateways = gateways.sorted()
    }
}

struct NetworkChangeDetector: Sendable {
    /// 最近一个“可用”的网络；不可用的快照不覆盖它。
    private(set) var last: NetworkFingerprint?

    /// 喂入一次路径更新；返回 true 表示默认底层网络变了（需执行 §16.a③ 的统一动作）。
    mutating func observe(_ fp: NetworkFingerprint, reasserting: Bool = false) -> Bool {
        guard !reasserting else { return false }
        guard fp.satisfied, fp.primaryInterface != nil else { return false }
        let previous = last
        last = fp
        guard let previous else { return false }   // 基线
        return previous.primaryInterface != fp.primaryInterface || previous.gateways != fp.gateways
    }

    /// 隧道重新启动时清空基线。
    mutating func reset() { last = nil }
}

/// 去抖：`schedule` 后 `delay` 内再次 `schedule` 只保留最后一次；`cancel` 取消未执行的。线程安全，回调在 `queue` 上。
final class Debouncer: @unchecked Sendable {
    static let networkChangeDelay: TimeInterval = 2

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generation = 0

    init(delay: TimeInterval, queue: DispatchQueue) {
        self.delay = delay
        self.queue = queue
    }

    func schedule(_ action: @escaping @Sendable () -> Void) {
        lock.lock(); generation += 1; let g = generation; lock.unlock()
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let current = self.generation == g; self.lock.unlock()
            if current { action() }
        }
    }

    func cancel() {
        lock.lock(); generation += 1; lock.unlock()
    }
}

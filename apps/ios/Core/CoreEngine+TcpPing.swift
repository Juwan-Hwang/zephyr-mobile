// 隧道未连接时的测速（契约 §14.u）：App 进程直接测到节点 server:port 的 TCP 握手时间。
// 连上后仍走扩展内 zm_url_test（经代理的真实 URL 测试）。握手时间反映到入口的网络距离，不含代理协议开销。

import Foundation
import Network
import ZephyrKit

extension CoreEngine {
    /// 同时在途的握手数（太大易被运营商当成扫描、也挤占主线程网络回调）。
    public static let tcpPingConcurrency = 32
    public static let tcpPingTimeout: TimeInterval = 3

    /// 进程级握手名额：滚动触发的多批测速同时在途时，总并发仍不超过 tcpPingConcurrency。
    static let pingSlot = AsyncLimiter(tcpPingConcurrency)

    /// 一次 TCP 握手耗时（毫秒）；失败、拒绝、超时为 -1。
    public static func tcpHandshake(host: String, port: UInt16, timeout: TimeInterval = tcpPingTimeout) async -> Int32 {
        guard let p = NWEndpoint.Port(rawValue: port), !host.isEmpty else { return -1 }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let queue = DispatchQueue(label: "zephyr.tcpping")
        let start = DispatchTime.now()
        return await withCheckedContinuation { (k: CheckedContinuation<Int32, Never>) in
            let done = OneShot()
            @Sendable func finish(_ v: Int32) {
                guard done.fire() else { return }
                conn.stateUpdateHandler = nil   // 断开 conn → handler → finish → conn 的引用环
                conn.cancel()
                k.resume(returning: v)
            }
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(Int32(clamping: max(1, ns / 1_000_000)))
                case .failed, .cancelled:
                    finish(-1)
                // .waiting 可能是暂时的（网络路径切换），交给超时处理
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(-1) }
            conn.start(queue: queue)
        }
    }

    /// 未连接时的测速：核心给出目标（UDP 协议节点跳过），并发握手，结果写回核心延迟缓存并推送。
    func tcpPing(_ c: MobileCore, ids: [NodeId]) async {
        for start in stride(from: 0, to: ids.count, by: 512) {
            if Task.isCancelled { return }
            let chunk = Array(ids[start..<min(start + 512, ids.count)])
            guard let targets = try? await run(.nodeNotFound, { try c.tcpPingTargets(ids: chunk) }), !targets.isEmpty else { continue }
            var results: [(UInt64, Int32)] = []
            await withTaskGroup(of: (UInt64, Int32).self) { g in
                var it = targets.makeIterator()
                for _ in 0..<CoreEngine.tcpPingConcurrency {
                    guard let t = it.next() else { break }
                    g.addTask { await CoreEngine.pingSlot.run { (t.id, await CoreEngine.tcpHandshake(host: t.host, port: t.port)) } }
                }
                while let r = await g.next() {
                    results.append(r)
                    if Task.isCancelled { continue }
                    if let t = it.next() {
                        g.addTask { await CoreEngine.pingSlot.run { (t.id, await CoreEngine.tcpHandshake(host: t.host, port: t.port)) } }
                    }
                }
            }
            let now = self.now()
            let samples = results.map { LatencySample(id: $0.0, ms: $0.1, at: now) }
            guard !samples.isEmpty, (try? await run(.nodeNotFound, { try c.recordLatencies(samples: samples) })) != nil else { continue }
            let updates = samples.map { LatencyUpdate(id: $0.id, latencyMs: $0.ms, at: $0.at) }
            for w in locked({ Array(latencyWatchers.values) }) { w.yield(updates) }
        }
    }
}

/// 简单的异步并发上限（FIFO 等待）。
actor AsyncLimiter {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { free = n }

    func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await acquire()
        let r = await body()
        release()
        return r
    }

    private func acquire() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() }
    }
}

/// 只放行第一次。
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

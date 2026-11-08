// SharedBroadcast —— 一个上游流扇出给多个订阅者（REVIEW-Q2 X-P1-3）。
//
// 流量流此前由 AppModel 与 SharedStatePublisher 各自订阅，每个订阅者各自 1 Hz 向扩展发 provider message；
// 现在第一个订阅者启动上游、最后一个取消时停止上游，期间所有订阅者共享同一次轮询。
// 不回放历史值：晚到的订阅者从下一次采样开始（流量是瞬时量，回放旧值反而误导）。

import Foundation

final class SharedBroadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var pump: Task<Void, Never>?
    /// 每次启动上游递增；已被取消的旧上游收尾时不得清掉新一代订阅者。
    private var generation = 0

    /// 订阅者数量（测试用）。
    var subscriberCount: Int { lock.lock(); defer { lock.unlock() }; return subscribers.count }

    /// `upstream` 仅在从 0 → 1 个订阅者时调用一次。
    func subscribe(upstream: @escaping @Sendable () -> AsyncStream<Element>) -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.lock()
        subscribers[id] = continuation
        let needsPump = pump == nil
        if needsPump {
            generation += 1
            let mine = generation
            pump = Task { [weak self] in
                for await value in upstream() {
                    guard let self else { return }
                    self.emit(value)
                }
                self?.finishAll(generation: mine)
            }
        }
        lock.unlock()
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        return stream
    }

    private func emit(_ value: Element) {
        lock.lock()
        let targets = Array(subscribers.values)
        lock.unlock()
        for c in targets { c.yield(value) }
    }

    private func finishAll(generation g: Int) {
        lock.lock()
        guard g == generation else { lock.unlock(); return }
        let targets = Array(subscribers.values)
        subscribers = [:]
        pump = nil
        lock.unlock()
        for c in targets { c.finish() }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: id)
        var stale: Task<Void, Never>?
        if subscribers.isEmpty { stale = pump; pump = nil }
        lock.unlock()
        stale?.cancel()
    }
}

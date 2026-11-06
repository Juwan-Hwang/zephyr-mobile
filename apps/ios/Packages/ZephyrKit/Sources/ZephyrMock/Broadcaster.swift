// 线程安全的多订阅者 AsyncStream 广播。订阅时可立即补发当前值。

import Foundation

final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSRecursiveLock()   // 保证"当前值先于后续变化"的顺序；yield 期间持锁
    private var conts: [UUID: (AsyncStream<Element>.Continuation, @Sendable (Element) -> Bool)] = [:]

    /// `initial` 在注册后立即发出；`filter` 决定该订阅者接收哪些元素。
    func stream(initial: [Element] = [], filter: @escaping @Sendable (Element) -> Bool = { _ in true }) -> AsyncStream<Element> {
        let (stream, cont) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        cont.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.conts[id] = nil; self.lock.unlock()
        }
        lock.lock()
        conts[id] = (cont, filter)
        for e in initial where filter(e) { cont.yield(e) }
        lock.unlock()
        return stream
    }

    func send(_ e: Element) {
        lock.lock(); defer { lock.unlock() }
        for (c, f) in conts.values where f(e) { c.yield(e) }
    }

    var subscriberCount: Int { lock.lock(); defer { lock.unlock() }; return conts.count }

    deinit { for (c, _) in conts.values { c.finish() } }
}

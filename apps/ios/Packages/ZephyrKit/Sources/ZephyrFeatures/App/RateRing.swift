// 固定容量环形缓冲（首页曲线：300 点 ≈ 5 分钟 @1 Hz）。
// 值类型、无分配的 append；按时间顺序遍历。纯 Swift，不依赖 SwiftUI。

import Foundation

public struct RatePoint: Hashable, Sendable {
    /// 毫秒 Unix 时间戳（契约 §0.4）
    public var at: Int64
    /// 字节/秒
    public var down: Int64
    public var up: Int64
    public init(at: Int64, down: Int64, up: Int64) { self.at = at; self.down = down; self.up = up }
}

public struct RateRing: Sendable, Equatable {
    public let capacity: Int
    private var storage: [RatePoint]
    private var head = 0          // 下一个写入位置
    public private(set) var count = 0

    public init(capacity: Int = 300) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    public var isEmpty: Bool { count == 0 }

    public mutating func append(_ p: RatePoint) {
        if storage.count < capacity {
            storage.append(p)
        } else {
            storage[head] = p
        }
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    public mutating func append<S: Sequence>(contentsOf ps: S) where S.Element == RatePoint {
        for p in ps { append(p) }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true); head = 0; count = 0
    }

    /// 第 i 个（0 = 最旧）。
    public subscript(i: Int) -> RatePoint {
        precondition(i >= 0 && i < count)
        let start = storage.count < capacity ? 0 : head
        return storage[(start + i) % capacity]
    }

    public var last: RatePoint? { count == 0 ? nil : self[count - 1] }

    /// 最近 n 个，按时间升序。
    public func suffix(_ n: Int) -> [RatePoint] {
        let k = min(n, count)
        return (count - k..<count).map { self[$0] }
    }

    /// 全部，按时间升序。
    public var ordered: [RatePoint] { suffix(count) }

    /// 最近 n 个点里的下行峰值（曲线归一化用）。
    public func peakDown(last n: Int) -> Int64 {
        var m: Int64 = 0
        let k = min(n, count)
        for i in (count - k)..<count { m = max(m, self[i].down) }
        return m
    }

    public static func == (a: RateRing, b: RateRing) -> Bool { a.capacity == b.capacity && a.ordered == b.ordered }
}

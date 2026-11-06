// LRUCache — 节点页缓存（纯 Swift，可单测）。
//
// 容量小（默认 64 页 × 128 行 ≈ 8k 节点，约 1 MB），用“字典 + 双向链表（数组下标）”实现 O(1) 读写与淘汰，
// 滚动热路径上不分配对象。

import Foundation

struct LRUCache<Key: Hashable, Value> {
    private struct Entry {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    let capacity: Int
    private var map: [Key: Int] = [:]
    private var entries: [Entry] = []
    private var head = -1   // 最近使用
    private var tail = -1   // 最久未用

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        map.reserveCapacity(capacity)
        entries.reserveCapacity(capacity)
    }

    var count: Int { map.count }

    /// 读取并标记为最近使用。
    mutating func value(for key: Key) -> Value? {
        guard let i = map[key] else { return nil }
        moveToFront(i)
        return entries[i].value
    }

    /// 只读，不改变顺序（用于判断是否已缓存）。
    func peek(_ key: Key) -> Value? {
        map[key].map { entries[$0].value }
    }

    func contains(_ key: Key) -> Bool { map[key] != nil }

    mutating func insert(_ value: Value, for key: Key) {
        if let i = map[key] {
            entries[i].value = value
            moveToFront(i)
            return
        }
        if entries.count < capacity {
            entries.append(Entry(key: key, value: value, prev: -1, next: -1))
            let i = entries.count - 1
            map[key] = i
            pushFront(i)
        } else {
            // 复用最久未用的槽位。
            let i = tail
            unlink(i)
            map[entries[i].key] = nil
            entries[i].key = key
            entries[i].value = value
            map[key] = i
            pushFront(i)
        }
    }

    /// 原地修改已缓存的值（例如写入新测得的延迟），不改变顺序。返回是否命中。
    @discardableResult
    mutating func update(_ key: Key, _ body: (inout Value) -> Void) -> Bool {
        guard let i = map[key] else { return false }
        body(&entries[i].value)
        return true
    }

    mutating func removeAll() {
        map.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        head = -1; tail = -1
    }

    /// 按最近使用顺序列出 key（测试用）。
    var keysByRecency: [Key] {
        var out: [Key] = []
        var i = head
        while i >= 0 { out.append(entries[i].key); i = entries[i].next }
        return out
    }

    // MARK: 链表

    private mutating func unlink(_ i: Int) {
        let p = entries[i].prev, n = entries[i].next
        if p >= 0 { entries[p].next = n } else { head = n }
        if n >= 0 { entries[n].prev = p } else { tail = p }
        entries[i].prev = -1; entries[i].next = -1
    }

    private mutating func pushFront(_ i: Int) {
        entries[i].prev = -1
        entries[i].next = head
        if head >= 0 { entries[head].prev = i }
        head = i
        if tail < 0 { tail = i }
    }

    private mutating func moveToFront(_ i: Int) {
        guard head != i else { return }
        unlink(i)
        pushFront(i)
    }
}

// SharedStore —— SharedState 的跨进程读写。
//
//  - 写：NSFileCoordinator 协调（App / PacketTunnel / 小组件可能同时写）+ `.atomic`（临时文件 + rename），
//    读者永远看不到半个文件；文件保护 `completeUntilFirstUserAuthentication`，锁屏时扩展仍可读。
//  - 写完发 Darwin 通知 `DarwinNotification.stateChanged`，其他进程据此刷新。
//  - 读：按修改时间缓存，小组件时间线频繁读取也不重复解码。
//  - `update { }` 是“读-改-写”，只改自己负责的字段，不覆盖别的进程写的部分。

import Foundation

final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    let url: URL
    private let lock = NSLock()
    private var cache: (modified: Date, state: SharedState)?
    private let notify: Bool

    init(directory: URL = AppGroup.containerURL, fileName: String = "shared-state.json", notify: Bool = true) {
        self.url = directory.appendingPathComponent(fileName, isDirectory: false)
        self.notify = notify
    }

    // MARK: 读

    /// 读当前状态；文件不存在、损坏或 schema 不兼容时返回 `.empty`。
    func read() -> SharedState {
        lock.lock(); defer { lock.unlock() }
        return readLocked()
    }

    private func readLocked() -> SharedState {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let modified, let cache, cache.modified == modified { return cache.state }
        var result = SharedState.empty
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
            guard let data = try? Data(contentsOf: u),
                  let decoded = try? Self.decoder.decode(SharedState.self, from: data),
                  decoded.version == SharedState.schemaVersion
            else { return }
            result = decoded
        }
        if let modified { cache = (modified, result) }
        return result
    }

    // MARK: 写

    /// 整体写入。
    func write(_ state: SharedState) throws {
        try update { $0 = state }
    }

    /// 读-改-写（跨进程协调）。返回写入后的状态。
    @discardableResult
    func update(_ body: (inout SharedState) -> Void) throws -> SharedState {
        lock.lock(); defer { lock.unlock() }
        var coordError: NSError?
        var writeError: Error?
        var written = SharedState.empty
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [.forMerging], error: &coordError) { u in
            var state = SharedState.empty
            if let data = try? Data(contentsOf: u),
               let decoded = try? Self.decoder.decode(SharedState.self, from: data),
               decoded.version == SharedState.schemaVersion {
                state = decoded
            }
            body(&state)
            state.version = SharedState.schemaVersion
            state.updatedAt = Date()
            do {
                let data = try Self.encoder.encode(state)
                try data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written = state
            } catch {
                writeError = error
            }
        }
        if let error = coordError ?? writeError { throw error }
        cache = nil
        if notify { DarwinNotifier.post(.stateChanged) }
        return written
    }

    /// 删除（单测 / “清除数据”）。
    func reset() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
        cache = nil
    }

    // MARK: 编解码

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}

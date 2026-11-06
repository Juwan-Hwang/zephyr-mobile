// MihomoBridge —— libmihomo C ABI 的 Swift 包装（PacketTunnel 内唯一调用核心的地方）。
//
// mihomo 以静态库嵌入扩展进程（c-archive），禁止 Process()/posix_spawn 启子进程（iOS 也不允许）。
// 编译条件：
//   MIHOMO_LINKED 已定义 → 调用 include/mihomo.h 声明的真实符号（需要 A 提供的 Mihomo.xcframework）；
//   未定义（当前默认）    → 桩实现：记录状态、流量恒为 0，供单测和无核心的 CI 构建。
//                          ZephyrPacketTunnelProvider 在桩模式下拒绝启动隧道，避免“连上但全部流量黑洞”。

import Foundation

final class MihomoBridge: @unchecked Sendable {
    static let shared = MihomoBridge()

    struct Traffic: Sendable, Hashable {
        var up: Int64
        var down: Int64
        var upTotal: Int64
        var downTotal: Int64
        static let zero = Traffic(up: 0, down: 0, upTotal: 0, downTotal: 0)
    }

    enum BridgeError: Error, Sendable, Hashable {
        case alreadyRunning
        case notRunning
        case invalidArgument
        case core(code: Int32, message: String)
    }

    /// 是否链接了真实的 libmihomo。
    static var isLinked: Bool {
        #if MIHOMO_LINKED
        return true
        #else
        return false
        #endif
    }

    private let lock = NSLock()
    private var running = false
    private var mode = "rule"
    private var memoryLimit: Int64 = 0

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }
    var currentMode: String { lock.lock(); defer { lock.unlock() }; return mode }

    // MARK: 生命周期

    func start(configPath: String, tunFD: Int32) throws {
        guard !configPath.isEmpty, tunFD >= 0 else { throw BridgeError.invalidArgument }
        lock.lock(); defer { lock.unlock() }
        guard !running else { throw BridgeError.alreadyRunning }
        #if MIHOMO_LINKED
        let rc = configPath.withCString { mihomo_start($0, tunFD) }
        guard rc == 0 else { throw BridgeError.core(code: rc, message: Self.lastError()) }
        #endif
        running = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        #if MIHOMO_LINKED
        mihomo_stop()
        #endif
        running = false
    }

    func reload(configPath: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard running else { throw BridgeError.notRunning }
        #if MIHOMO_LINKED
        let rc = configPath.withCString { mihomo_reload($0) }
        guard rc == 0 else { throw BridgeError.core(code: rc, message: Self.lastError()) }
        #endif
    }

    // MARK: 运行时

    func traffic() -> Traffic {
        #if MIHOMO_LINKED
        guard isRunning else { return .zero }
        let t = mihomo_traffic()
        return Traffic(up: t.up, down: t.down, upTotal: t.up_total, downTotal: t.down_total)
        #else
        return .zero
        #endif
    }

    /// "rule" | "global" | "direct"
    func setMode(_ newMode: String) {
        lock.lock(); defer { lock.unlock() }
        mode = newMode
        #if MIHOMO_LINKED
        if running { _ = newMode.withCString { mihomo_set_mode($0) } }
        #endif
    }

    func setMemoryLimit(bytes: Int64) {
        lock.lock(); defer { lock.unlock() }
        memoryLimit = bytes
        #if MIHOMO_LINKED
        mihomo_set_memory_limit(bytes)
        #endif
    }

    func freeOSMemory() {
        #if MIHOMO_LINKED
        mihomo_free_os_memory()
        #endif
    }

    #if MIHOMO_LINKED
    private static func lastError() -> String {
        guard let p = mihomo_last_error() else { return "" }
        return String(cString: p)
    }
    #endif
}

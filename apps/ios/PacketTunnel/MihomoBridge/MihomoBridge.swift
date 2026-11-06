// MihomoBridge —— 嵌入式 mihomo（mihomo-mobile，Zmihomo.xcframework，c-archive）的 Swift 包装。PacketTunnel 内唯一调用核心的地方。
//
// C ABI 见 mihomo-mobile/zmihomo.go：zm_start(home, yaml, ctlSock) / zm_reload / zm_stop / zm_running / zm_traffic /
// zm_memory / zm_set_memory_limit / zm_free_os_memory / zm_version / zm_free。返回 char* 的函数：NULL = 成功，否则错误串（zm_free）。
//
// 配置由 App 侧 Rust 核心生成（CoreEngine.writeTunnelConfig），tun.file-descriptor 写哨兵值 -1；
// 扩展拿到 utun fd 后用 `injectingTunFD` 替换再启动（扩展进程不链接 Rust 核心，省 NE 内存）。
//
// 编译条件：MIHOMO_LINKED（project.yml 的 PacketTunnel 已置位并链接 Zmihomo.xcframework）；
// 未定义时为桩实现（ZephyrTests 直接编译本文件），Provider 在桩模式下拒绝启动隧道，避免“连上但流量黑洞”。

import Foundation
#if MIHOMO_LINKED
import Zmihomo
#endif

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
        case core(message: String)
    }

    /// 是否链接了真实的 mihomo。
    static var isLinked: Bool {
        #if MIHOMO_LINKED
        return true
        #else
        return false
        #endif
    }

    /// 生成配置时写入的 fd 哨兵（契约 §14：iOS 由扩展替换为真实 utun fd）。
    static let fdSentinel = "file-descriptor: -1"

    private let lock = NSLock()
    private var running = false
    private var config = ""
    private var homeDir = ""
    private var controllerSocket = ""

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    var currentMode: String {
        lock.lock(); defer { lock.unlock() }
        return Self.mode(in: config) ?? "rule"
    }

    // MARK: 纯函数（可单测）

    /// 把哨兵替换成真实 fd；找不到哨兵返回 nil（配置不是给 iOS 隧道生成的）。
    static func injectingTunFD(_ yaml: String, fd: Int32) -> String? {
        guard fd >= 0, yaml.contains(fdSentinel) else { return nil }
        return yaml.replacingOccurrences(of: fdSentinel, with: "file-descriptor: \(fd)")
    }

    /// 顶层 `mode:` 行替换为 rule/global/direct；没有则追加。
    static func settingMode(_ yaml: String, _ mode: String) -> String {
        guard ["rule", "global", "direct"].contains(mode) else { return yaml }
        var lines = yaml.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.hasPrefix("mode:") }) {
            lines[i] = "mode: \(mode)"
            return lines.joined(separator: "\n")
        }
        return "mode: \(mode)\n" + yaml
    }

    static func mode(in yaml: String) -> String? {
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("mode:") {
            return line.dropFirst("mode:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: 生命周期

    /// - Parameters:
    ///   - homeDir: mihomo 工作目录（缓存、规则集、GeoIP），App Group/core。
    ///   - config: 已注入 fd 的 YAML 正文。
    ///   - controllerSocket: external-controller-unix 路径（App 经它读策略组/连接）。
    func start(homeDir: String, config: String, controllerSocket: String) throws {
        guard !homeDir.isEmpty, !config.isEmpty else { throw BridgeError.invalidArgument }
        lock.lock(); defer { lock.unlock() }
        guard !running else { throw BridgeError.alreadyRunning }
        #if MIHOMO_LINKED
        if let err = Self.call3(homeDir, config, controllerSocket, zm_start) { throw BridgeError.core(message: err) }
        #endif
        self.homeDir = homeDir
        self.config = config
        self.controllerSocket = controllerSocket
        running = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        #if MIHOMO_LINKED
        zm_stop()
        #endif
        running = false
    }

    /// 用新的 YAML（已注入 fd）热重载。
    func reload(config newConfig: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard running else { throw BridgeError.notRunning }
        #if MIHOMO_LINKED
        if let err = Self.call1(newConfig, zm_reload) { throw BridgeError.core(message: err) }
        #endif
        config = newConfig
    }

    /// "rule" | "global" | "direct"：改配置的 mode 行并热重载（不重建 TUN）。
    func setMode(_ newMode: String) throws {
        let next: String
        lock.lock()
        let wasRunning = running
        next = Self.settingMode(config, newMode)
        if !wasRunning { config = next }
        lock.unlock()
        if wasRunning { try reload(config: next) }
    }

    // MARK: 运行时

    func traffic() -> Traffic {
        #if MIHOMO_LINKED
        guard isRunning else { return .zero }
        var up: Int64 = 0, down: Int64 = 0, upTotal: Int64 = 0, downTotal: Int64 = 0
        zm_traffic(&up, &down, &upTotal, &downTotal)
        return Traffic(up: up, down: down, upTotal: upTotal, downTotal: downTotal)
        #else
        return .zero
        #endif
    }

    /// mihomo 自报内存（字节）。
    func coreMemory() -> Int64 {
        #if MIHOMO_LINKED
        return Int64(zm_memory())
        #else
        return 0
        #endif
    }

    func setMemoryLimit(bytes: Int64) {
        #if MIHOMO_LINKED
        zm_set_memory_limit(bytes)
        #endif
    }

    func freeOSMemory() {
        #if MIHOMO_LINKED
        zm_free_os_memory()
        #endif
    }

    var version: String {
        #if MIHOMO_LINKED
        guard let p = zm_version() else { return "" }
        defer { zm_free(p) }
        return String(cString: p)
        #else
        return "stub"
        #endif
    }

    // MARK: C 字符串调用

    #if MIHOMO_LINKED
    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { zm_free(p) }
        let s = String(cString: p)
        return s.isEmpty ? "unknown error" : s
    }

    private static func call1(_ a: String, _ f: (UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?) -> String? {
        a.withCString { pa in take(f(UnsafeMutablePointer(mutating: pa))) }
    }

    private static func call3(_ a: String, _ b: String, _ c: String,
                              _ f: (UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?) -> String? {
        a.withCString { pa in b.withCString { pb in c.withCString { pc in
            take(f(UnsafeMutablePointer(mutating: pa), UnsafeMutablePointer(mutating: pb), UnsafeMutablePointer(mutating: pc)))
        } } }
    }
    #endif
}

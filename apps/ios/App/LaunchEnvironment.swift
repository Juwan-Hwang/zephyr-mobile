// 启动环境：用哪个引擎、是否冻结时钟、是否在跑测试。
//
// 启动参数（Xcode scheme → Arguments，或 xcrun simctl launch … -ZephyrEngine mock）：
//   -ZephyrEngine mock|core     强制引擎（core 需要 ZephyrCore 模块 + Release 的 ZEPHYR_CORE_ENGINE 条件）
//   -ZephyrClock frozen941      时钟冻结在原型 9:41（录屏 / 截图 / UI 测试）
//   -ZephyrSeed <n>             MockEngine 种子

import Foundation

struct LaunchEnvironment: Sendable {
    enum EngineKind: String, Sendable {
        case mock, core
    }

    var engine: EngineKind
    var frozenClock: Bool
    var seed: UInt64
    var isRunningTests: Bool

    /// 是否由系统 VPN（NEPacketTunnel）承载流量：只有真机上的 CoreEngine。
    var usesSystemTunnel: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return engine == .core
        #endif
    }

    static func current(processInfo: ProcessInfo = .processInfo, defaults: UserDefaults = .standard) -> LaunchEnvironment {
        let isTests = processInfo.environment["XCTestConfigurationFilePath"] != nil
        let requested = defaults.string(forKey: "ZephyrEngine").flatMap(EngineKind.init(rawValue:))
        #if DEBUG || targetEnvironment(simulator)
        let fallback = EngineKind.mock
        #else
        let fallback = EngineKind.core
        #endif
        return LaunchEnvironment(
            engine: isTests ? .mock : (requested ?? fallback),
            frozenClock: isTests || defaults.string(forKey: "ZephyrClock") == "frozen941",
            seed: UInt64(max(0, defaults.integer(forKey: "ZephyrSeed"))),
            isRunningTests: isTests
        )
    }
}

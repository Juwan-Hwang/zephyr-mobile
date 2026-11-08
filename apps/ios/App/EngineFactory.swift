// EngineFactory —— 依赖注入的唯一位置。
//
// MockEngine：Debug、模拟器、测试、Preview（确定性数据，移植原型 pages.js）。
// CoreEngine：Release 默认（或 -ZephyrEngine core）。ZephyrCore 是 project.yml 里的静态框架（Rust core-mobile + UniFFI），
//             Debug 下 core 环境用 MockEngine 兜底空库（mockData），Release 空库即空状态。

import Foundation
import os
import ZephyrKit
import ZephyrMock
#if canImport(ZephyrCore)
import ZephyrCore
#endif

enum EngineFactory {
    struct Built: Sendable {
        let engine: any ZephyrEngine
        /// AppModel 的时钟（毫秒）。冻结时钟时与 MockEngine 同源，首页时长 / “2 小时前”稳定。
        let now: @Sendable () -> Int64
        /// 实际生效的环境（请求 core 但不可用时已改成 mock）。
        let environment: LaunchEnvironment
        /// Release 下真核心没能加载：不再回落 MockEngine（会把演示数据当真的展示），App 显示不可用页（REVIEW-Q2 X-P0-2）。
        var coreUnavailable: Bool = false
    }

    private static let log = Logger(subsystem: "app.zephyr.mobile", category: "engine")

    static func make(_ requested: LaunchEnvironment) -> Built {
        var environment = requested
        if environment.engine == .core {
            #if canImport(ZephyrCore)
            #if DEBUG
            let mockData = true
            #else
            let mockData = false
            #endif
            // 真机：连接 / 流量 / 策略组 / 连接列表经系统隧道与 mihomo 控制口（SystemTunnelPort + MihomoClient）。
            let tunnel: (any TunnelPort)? = environment.usesSystemTunnel ? SystemTunnelPort() : nil
            let engine = CoreEngine(fallback: MockEngine(seed: environment.seed, clock: .live), mockData: mockData, tunnel: tunnel)
            if engine.isNative {
                return Built(engine: engine, now: { ZFormat.nowMillis() }, environment: environment)
            }
            log.error("Rust 核心加载失败")
            #if DEBUG
            environment.engine = .mock
            #else
            return Built(engine: engine, now: { ZFormat.nowMillis() }, environment: environment, coreUnavailable: true)
            #endif
            #else
            log.warning("CoreEngine 不可用（未链接 ZephyrCore）")
            #if DEBUG
            environment.engine = .mock
            #else
            let stub = MockEngine(seed: 0, clock: .live)
            return Built(engine: stub, now: { ZFormat.nowMillis() }, environment: environment, coreUnavailable: true)
            #endif
            #endif
        }
        let clock: MockClock = environment.frozenClock ? .frozen941 : .live
        let engine = MockEngine(seed: environment.seed, clock: clock)
        return Built(engine: engine, now: { clock.now() }, environment: environment)
    }
}

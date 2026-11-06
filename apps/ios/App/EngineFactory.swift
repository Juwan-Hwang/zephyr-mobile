// EngineFactory —— 依赖注入的唯一位置。
//
// MockEngine：Debug、模拟器、测试、Preview（确定性数据，移植原型 pages.js）。
// CoreEngine：Release 真机。编译条件 ZEPHYR_CORE_ENGINE（project.yml 的 Release 配置已置位）且
//             ZephyrCore 模块可导入时才启用；否则回落 MockEngine 并打日志——保证 CI 与当前包结构下能构建。

import Foundation
import os
import ZephyrKit
import ZephyrMock
#if ZEPHYR_CORE_ENGINE && canImport(ZephyrCore)
import ZephyrCore
#endif

enum EngineFactory {
    struct Built: Sendable {
        let engine: any ZephyrEngine
        /// AppModel 的时钟（毫秒）。冻结时钟时与 MockEngine 同源，首页时长 / “2 小时前”稳定。
        let now: @Sendable () -> Int64
        /// 实际生效的环境（请求 core 但不可用时已改成 mock）。
        let environment: LaunchEnvironment
    }

    private static let log = Logger(subsystem: "app.zephyr.mobile", category: "engine")

    static func make(_ requested: LaunchEnvironment) -> Built {
        var environment = requested
        if environment.engine == .core {
            #if ZEPHYR_CORE_ENGINE && canImport(ZephyrCore)
            // CoreEngine 的初始化签名由 K/A 定义（ZephyrCore 尚未加入 Package.swift）；到位后在此对齐。
            let engine = CoreEngine()
            return Built(engine: engine, now: { ZFormat.nowMillis() }, environment: environment)
            #else
            log.warning("CoreEngine 不可用（未链接 ZephyrCore），回落 MockEngine")
            environment.engine = .mock
            #endif
        }
        let clock: MockClock = environment.frozenClock ? .frozen941 : .live
        let engine = MockEngine(seed: environment.seed, clock: clock)
        return Built(engine: engine, now: { clock.now() }, environment: environment)
    }
}

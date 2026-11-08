// EngineHost —— 进程内唯一的引擎实例。
// 前台启动（AppBootstrap）与后台刷新任务（SubscriptionAutoUpdater）共用：两处各开一个 MobileCore 会同时写同一份数据目录。
// actor 的同步方法跑在协作线程池，不占主线程；首次调用才真正加载核心。

import Foundation

actor EngineHost {
    static let shared = EngineHost()

    private var built: EngineFactory.Built?

    func get() -> EngineFactory.Built {
        if let built { return built }
        let value = EngineFactory.make(LaunchEnvironment.current())
        built = value
        return value
    }
}

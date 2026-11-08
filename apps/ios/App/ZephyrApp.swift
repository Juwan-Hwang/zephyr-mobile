// Zephyr App 入口（极薄）：选引擎 → 建 AppModel → 安装平台服务（NE、App Group、实时活动、App Intents）→ RootView。
//
// 引擎：Debug / 模拟器 / 测试 → MockEngine；Release 真机 → CoreEngine（ZephyrCore 就绪后，见 EngineFactory）。
// 深链：zephyr:// 由 RootView 内的 AppModel.handle(url:) 处理；clash:// / mihomo:// 的“导入订阅”由这里处理。

import SwiftUI
import ZephyrFeatures

@main
@MainActor
struct ZephyrApp: App {
    @State private var model: AppModel
    private let services: AppServices
    private let coreUnavailable: Bool

    init() {
        let environment = LaunchEnvironment.current()
        let built = EngineFactory.make(environment)
        let model = AppModel(engine: built.engine, now: built.now)
        let services = AppServices(engine: built.engine, environment: built.environment)
        services.install(on: model)
        _model = State(initialValue: model)
        self.services = services
        self.coreUnavailable = built.coreUnavailable
    }

    // 注意：ZephyrKit 也有 `Scene`（场景模型），这里必须写全 SwiftUI.Scene。
    var body: some SwiftUI.Scene {
        WindowGroup {
            if coreUnavailable {
                CoreUnavailableView()
            } else {
                RootView(model: model)
                    .onOpenURL { services.handleExternal(url: $0, model: model) }
                    .task { services.start(model: model) }
            }
        }
    }
}

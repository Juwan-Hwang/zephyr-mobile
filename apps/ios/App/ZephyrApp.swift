// Zephyr App 入口（极薄）：先呈现启动画面，AppBootstrap 在后台加载引擎 → 建 AppModel → 安装平台服务（NE、App Group、实时活动、App Intents）→ RootView。
//
// 引擎：Debug / 模拟器 / 测试 → MockEngine；Release 真机 → CoreEngine（ZephyrCore 就绪后，见 EngineFactory）。
// 深链：zephyr:// 由 RootView 内的 AppModel.handle(url:) 处理；clash:// / mihomo:// 的“导入订阅”经确认弹窗后由 AppServices 处理。

import SwiftUI
import ZephyrFeatures

@main
@MainActor
struct ZephyrApp: App {
    @State private var bootstrap = AppBootstrap()

    // 注意：ZephyrKit 也有 `Scene`（场景模型），这里必须写全 SwiftUI.Scene。
    var body: some SwiftUI.Scene {
        WindowGroup {
            Group {
                switch bootstrap.phase {
                case .loading:
                    LaunchScreenView()
                case .unavailable:
                    CoreUnavailableView()
                case .ready(let model, let services):
                    ReadyRoot(model: model, services: services)
                }
            }
            .onOpenURL { bootstrap.open($0) }
            .task { await bootstrap.run() }
        }
    }
}

/// 引擎就绪后的根：RootView + 平台服务启动 + 外部导入确认。
private struct ReadyRoot: View {
    let model: AppModel
    let services: AppServices

    var body: some View {
        RootView(model: model)
            .task { services.start(model: model) }
            .alert(
                Text("导入订阅？"),
                isPresented: Binding(
                    get: { services.importPrompt.request != nil },
                    set: { if !$0 { services.importPrompt.request = nil } }
                ),
                presenting: services.importPrompt.request
            ) { request in
                Button("导入") { services.confirmImport(request, model: model) }
                Button("取消", role: .cancel) {}
            } message: { request in
                Text(verbatim: request.message)
            }
    }
}

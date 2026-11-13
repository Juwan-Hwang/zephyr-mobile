// AppBootstrap —— 冷启动：先立刻呈现启动画面，再在后台线程加载引擎（Rust 核心 MobileCore 的初始化会读盘 / 建库），
// 就绪后在主线程建 AppModel 与平台服务（REVIEW-Q2 X-P1-14：此前在 App.init 里同步初始化，拖慢首帧）。
//
// 启动期间收到的深链先排队，就绪后回放：zephyr:// 交给 AppModel.handle，其余（clash:// / mihomo://）交给 AppServices。

import Foundation
import Observation
import ZephyrFeatures

@MainActor
@Observable
final class AppBootstrap {
    enum Phase {
        case loading
        case ready(AppModel, AppServices)
        case unavailable
    }

    private(set) var phase: Phase = .loading
    @ObservationIgnored private var started = false
    @ObservationIgnored private var queued: [URL] = []

    /// RootView 的 `.task` 之外的入口：幂等。
    func run() async {
        guard !started else { return }
        started = true
        // EngineHost 在后台执行器上加载引擎（打开核心库会阻塞），主线程继续渲染启动画面；
        // 后台刷新任务共用同一实例，避免两个 MobileCore 同时写一份数据目录。
        let built = await EngineHost.shared.get()
        if built.coreUnavailable {
            phase = .unavailable
            return
        }
        let model = AppModel(engine: built.engine, now: built.now)
        let services = AppServices(engine: built.engine, environment: built.environment)
        services.install(on: model)
        phase = .ready(model, services)
        let pending = queued
        queued = []
        for url in pending { route(url, model: model, services: services) }
    }

    func open(_ url: URL) {
        guard case .ready(let model, let services) = phase else {
            if case .loading = phase { queued.append(url) }
            return
        }
        // zephyr:// 已由 RootView 自己的 onOpenURL 处理，避免重复；桌面同步码 zephyr://import 例外（导入走确认弹窗）。
        guard url.scheme?.lowercased() != "zephyr" || ImportRequest.isDesktopSync(url) else { return }
        route(url, model: model, services: services)
    }

    private func route(_ url: URL, model: AppModel, services: AppServices) {
        if url.scheme?.lowercased() == "zephyr", !ImportRequest.isDesktopSync(url) {
            model.handle(url: url)
        } else {
            services.handleExternal(url: url, model: model)
        }
    }
}

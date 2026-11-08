// AppServices —— App 进程里的平台服务，生命周期 = App。
//
//  - 把 AppModel 注册为 App Intents 的执行者（ConnectionControl.inProcess）。
//  - 系统 VPN：真机 CoreEngine 的 connect() 经 SystemTunnelPort 写配置并启动 NEPacketTunnel。
//  - SharedStatePublisher：引擎流 → App Group 摘要 → 小组件 / 控制中心 reload。
//  - LiveActivityController：连接期间维持实时活动 + 灵动岛。
//  - PendingCommand：模拟器上扩展（控制中心 / 小组件）投递的命令。
//  - clash:// / mihomo:// install-config 导入订阅。
// 测试进程（XCTest）里什么都不启动。

import Foundation
import Observation
import os
import ZephyrFeatures
import ZephyrKit

@MainActor
final class AppServices {
    let engine: any ZephyrEngine
    let environment: LaunchEnvironment

    private let publisher: SharedStatePublisher
    private let liveActivity = LiveActivityController()
    private var commandObservation: DarwinObservation?
    private var started = false
    private let log = Logger(subsystem: "app.zephyr.mobile", category: "services")

    init(engine: any ZephyrEngine, environment: LaunchEnvironment) {
        self.engine = engine
        self.environment = environment
        self.publisher = SharedStatePublisher(engine: engine)
    }

    /// 在 RootView 出现之前调用：注入连接前钩子与 Intent 执行者。
    func install(on model: AppModel) {
        ConnectionControl.inProcess = ModelConnectionControl(model: model)
        // 真机 CoreEngine 自己经 SystemTunnelPort 生成配置并启动 NEPacketTunnel，无需 beforeConnect。
    }

    /// RootView 的 .task 里调用；幂等。
    func start(model: AppModel) {
        guard !started, !environment.isRunningTests else { return }
        started = true

        publisher.onChange = { [liveActivity] state, significant in
            liveActivity.sync(state, significant: significant)
        }
        publisher.start()

        commandObservation = DarwinNotifier.observe(.command) { [weak self] in
            Task { @MainActor in self?.drainCommands(model: model) }
        }
        drainCommands(model: model)
        SubscriptionAutoUpdater.shared.start()
    }

    // MARK: 扩展投递的命令

    private func drainCommands(model: AppModel) {
        guard let command = PendingCommandChannel.take() else { return }
        log.info("pending command: \(String(describing: command), privacy: .public)")
        Task {
            switch command {
            case .setConnected(true): await model.connect()
            case .setConnected(false): await model.disconnect()
            case .setMode(let mode): await model.setMode(ProxyMode(rawValue: mode.rawValue) ?? .rule)
            }
        }
    }

    // MARK: 外部链接（导入订阅）

    /// 待用户确认的导入请求（REVIEW-Q2 X-P1-1：外部链接不得静默导入）。
    let importPrompt = ImportPrompt()

    /// clash://install-config?url=<订阅地址>[&name=…]、mihomo://install-config?url=…
    /// 只弹出确认（显示域名；http 另加警告），用户点“导入”后才真正导入。zephyr:// 交给 RootView 里的 AppModel.handle(url:)，这里忽略。
    func handleExternal(url: URL, model: AppModel) {
        guard let payload = Self.subscriptionURL(from: url) else { return }
        importPrompt.request = ImportRequest(payload: payload)
    }

    func confirmImport(_ request: ImportRequest, model: AppModel) {
        importPrompt.request = nil
        Task {
            do {
                _ = try await engine.importSubscription(source: .url, payload: request.payload)
                model.push(.subscriptions)
            } catch let error as ZephyrError {
                model.lastError = error
            } catch {
                model.lastError = ZephyrError(code: .subscriptionInvalid, message: String(describing: error))
            }
        }
    }

    /// 解析导入链接；非 clash/mihomo 或缺少 url 参数返回 nil。
    nonisolated static func subscriptionURL(from url: URL) -> String? {
        ImportRequest.subscriptionURL(from: url)
    }
}

/// App Intents 在 App 进程内执行时走 AppModel（与首页开关同一条路径：错误提示、撤销、NE 启动钩子都一致）。
@MainActor
final class ModelConnectionControl: ConnectionControlling {
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func setConnected(_ on: Bool) async throws {
        model.lastError = nil   // 否则会把之前残留的错误当成本次失败（REVIEW-Q1 H-P2-22）
        if on { await model.connect() } else { await model.disconnect() }
        if let error = model.lastError { throw error }
    }

    func setMode(_ mode: SharedState.Mode) async throws {
        model.lastError = nil
        await model.setMode(ProxyMode(rawValue: mode.rawValue) ?? .rule)
        if let error = model.lastError { throw error }
    }
}

@MainActor
@Observable
final class ImportPrompt {
    var request: ImportRequest?
}

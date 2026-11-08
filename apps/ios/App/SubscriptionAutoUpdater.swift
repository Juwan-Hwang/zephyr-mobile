// SubscriptionAutoUpdater —— 订阅自动更新（REVIEW-Q2 X-P1-5）。
//
// 设置里的“自动更新间隔 / 仅 Wi‑Fi 更新”此前没有执行方。现在：
//   - BGAppRefreshTask（app.zephyr.mobile.refresh）：系统在合适的时机唤醒，更新到期的订阅，再排下一次；
//   - 回到前台 / 启动时检查一次（退避 15 分钟，失败不会反复重试）；
//   - “仅 Wi‑Fi”以 NWPath 判断：非计费、非受限网络才更新（蜂窝、个人热点、低数据模式都不更新）。
// 到期判断在 ZephyrKit.AutoUpdatePlanner（纯函数，有单测）。Mock 引擎（Debug / 模拟器）不自动更新。

import BackgroundTasks
import Foundation
import Network
import os
import UIKit
import ZephyrKit

@MainActor
final class SubscriptionAutoUpdater {
    nonisolated static let taskIdentifier = "app.zephyr.mobile.refresh"
    static let shared = SubscriptionAutoUpdater()

    private let log = Logger(subsystem: "app.zephyr.mobile", category: "auto-update")
    private var lastAttempt: [String: Int64] = [:]
    private var running = false
    private var observers: [NSObjectProtocol] = []

    /// 必须在 App 启动完成前注册（ZephyrApp.init）。测试进程不注册。
    nonisolated static func register() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task { @MainActor in
                let updated = await SubscriptionAutoUpdater.shared.runBackground()
                SubscriptionAutoUpdater.shared.schedule()
                task.setTaskCompleted(success: updated >= 0)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// RootView 出现后调用：前台检查 + 排期 + 监听前后台切换。
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in _ = await self?.runBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        schedule()
        Task { _ = await runBackground() }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do { try BGTaskScheduler.shared.submit(request) } catch {
            log.info("BG refresh 排期失败：\(String(describing: error), privacy: .public)")
        }
    }

    /// 更新所有到期订阅；返回成功个数，-1 表示被跳过（Mock 引擎 / 仅 Wi‑Fi 但不在 Wi‑Fi / 正在运行）。
    @discardableResult
    func runBackground() async -> Int {
        guard !running else { return -1 }
        running = true
        defer { running = false }
        let built = await EngineHost.shared.get()
        guard built.environment.engine == .core, !built.coreUnavailable else { return -1 }
        let engine = built.engine

        var subs: [Subscription] = []
        for await list in engine.subscriptions() { subs = list; break }
        var settings: Settings?
        for await s in engine.settings() { settings = s; break }

        let now = ZFormat.nowMillis()
        let ids = AutoUpdatePlanner.due(subs, settings: settings, now: now, lastAttempt: lastAttempt)
        guard !ids.isEmpty else { return 0 }
        if settings?.updateOnWifiOnly ?? true, !(await NetworkPathProbe.isUnmetered()) { return -1 }

        var updated = 0
        for id in ids {
            if Task.isCancelled { break }
            lastAttempt[id] = now
            if (try? await engine.updateSubscription(id: id)) != nil { updated += 1 }
        }
        log.info("自动更新：到期 \(ids.count, privacy: .public)，成功 \(updated, privacy: .public)")
        return updated
    }
}

/// 一次性判断当前网络是否“不计费且不受限”（Wi‑Fi / 以太网）。1.5 秒内没有结果按否处理。
enum NetworkPathProbe {
    static func isUnmetered() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "app.zephyr.mobile.pathprobe")
            let lock = NSLock()
            var done = false
            func finish(_ value: Bool) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                monitor.cancel()
                cont.resume(returning: value)
            }
            monitor.pathUpdateHandler = { path in
                finish(path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1.5) { finish(false) }
        }
    }
}

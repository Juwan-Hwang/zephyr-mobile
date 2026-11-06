// Darwin notify —— 跨进程“有新东西了”的信号（不带负载，负载在 App Group 文件里）。
//
//   DarwinNotifier.post(.stateChanged)
//   let token = DarwinNotifier.observe(.command) { … }      // 持有 token；释放即取消
//   for await _ in DarwinNotifier.stream(.stateChanged) { … }

import Foundation

enum DarwinNotification: String, CaseIterable, Sendable {
    /// SharedState 写入完成。
    case stateChanged = "app.zephyr.mobile.state-changed"
    /// 扩展（小组件 / 控制中心）投递了一条待 App 执行的命令（见 PendingCommand）。
    case command = "app.zephyr.mobile.command"
    /// PacketTunnel 的连接状态变化。
    case tunnelStatus = "app.zephyr.mobile.tunnel-status"

    var cfName: CFNotificationName { CFNotificationName(rawValue as CFString) }
}

enum DarwinNotifier {
    static func post(_ notification: DarwinNotification) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notification.cfName, nil, nil, true)
    }

    /// 观察通知。回调在任意线程触发；返回的 token 释放时自动取消观察。
    static func observe(_ notification: DarwinNotification, handler: @escaping @Sendable () -> Void) -> DarwinObservation {
        DarwinObservation(notification: notification, handler: handler)
    }

    /// 以 AsyncStream 形式观察；消费者取消时自动注销。
    static func stream(_ notification: DarwinNotification) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = DarwinObservation(notification: notification) { continuation.yield(()) }
            continuation.onTermination = { _ in token.cancel() }
        }
    }
}

/// 一次 Darwin 通知观察。C 回调不能捕获上下文，所以把自身指针作为 observer 传入，再取回 handler。
final class DarwinObservation: @unchecked Sendable {
    private let notification: DarwinNotification
    private let handler: @Sendable () -> Void
    private let lock = NSLock()
    private var active = false

    init(notification: DarwinNotification, handler: @escaping @Sendable () -> Void) {
        self.notification = notification
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<DarwinObservation>.fromOpaque(observer).takeUnretainedValue().fire()
        }, notification.rawValue as CFString, nil, .deliverImmediately)
        active = true
    }

    private func fire() {
        lock.lock(); let isActive = active; lock.unlock()
        if isActive { handler() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        active = false
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                           Unmanaged.passUnretained(self).toOpaque(), notification.cfName, nil)
    }

    deinit { cancel() }
}

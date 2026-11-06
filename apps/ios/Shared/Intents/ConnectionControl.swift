// ConnectionControl —— App Intents / 小组件按钮 / 控制中心开关 / 深链 的统一执行入口。
//
// 谁来执行：
//   1. App 进程：AppServices 启动时注册 `inProcess`（包装 ZephyrEngine），Intent 直接驱动引擎。
//   2. 扩展进程（小组件、控制中心）：没有引擎实例 → TunnelController：
//        真机：NETunnelProviderManager 启停 NE，模式经 provider message 发给 PacketTunnel；
//        模拟器：NE 不可用 → PendingCommand 投递给正在运行的 App。

import Foundation

protocol ConnectionControlling: Sendable {
    func setConnected(_ on: Bool) async throws
    func setMode(_ mode: SharedState.Mode) async throws
}

@MainActor
enum ConnectionControl {
    /// App 进程注册的引擎控制器（扩展进程里永远是 nil）。
    static var inProcess: (any ConnectionControlling)?

    static func resolve() -> any ConnectionControlling {
        inProcess ?? TunnelController.shared
    }

    /// 当前是否已连接（以共享摘要为准，扩展进程也可用）。
    static var isConnected: Bool { SharedStore.shared.read().connection.isOn }
}

// AppModel —— 全局唯一的应用状态：持有引擎、订阅实时流、管理导航。
//
// 视图约定
//  - 页面只读 AppModel 的属性；高频流量在 `traffic`（TrafficStore）里，只有速率/曲线小视图读取它。
//  - 写操作一律走 AppModel 的方法（AppModel+Actions.swift），方法内部 await 引擎并处理错误 / 撤销。
//  - 生命周期：RootView 出现时 `start()`；`scenePhaseChanged(_:)` 在进后台时暂停流量订阅、回前台时回填。

import Foundation
import Observation
import SwiftUI
import ZephyrKit

@MainActor
@Observable
public final class AppModel {

    // MARK: 依赖
    public let engine: any ZephyrEngine
    /// 当前时间（毫秒）。默认系统时钟；Preview / 快照注入 Mock 的 9:41 冻结时钟。
    @ObservationIgnored public let now: @Sendable () -> Int64
    /// 高频流量（1 Hz 样本 + 300 点历史）。
    public let traffic = TrafficStore()

    // MARK: 引擎状态（只读）
    public internal(set) var connection = ConnectionState(status: .disconnected, mode: .rule)
    public internal(set) var scenes: [Scene] = []
    public internal(set) var subscriptions: [Subscription] = []
    public internal(set) var usage: UsageSummary?
    /// 设置（强调色 / 外观在 RootView 统一应用）。
    public internal(set) var settings: Settings?
    /// 全局模式出口节点（由 connection.globalNodeId 解析）。
    public internal(set) var globalNode: NodeSummary?
    /// 正在重新检测的场景 id（首页"检测中"变体）。
    public internal(set) var retesting: Set<String> = []
    /// 首页左右滑动切换地区用：场景 id → 每个地区延迟最低的候选（按延迟升序）。
    public internal(set) var regionChoices: [String: [NodeSummary]] = [:]
    /// 待确认的场景切换（"更改 GPT 和 Gemini 的出口 IP？"）。
    public internal(set) var pendingChange: PendingSceneChange?
    /// 最近一次引擎错误（ZToast 展示后清空）。
    public var lastError: ZephyrError?

    // MARK: 导航
    /// NavigationStack 路径（节点 / 规则 / 订阅 / 设置，L 的页面）。
    public var path: [Route] = []
    /// 当前浮层。
    public var sheet: SheetRoute?
    /// 指令全屏层是否展开（原型 07）。
    public var isCommandPresented = false
    /// 打开指令层时预填的文字（深链 zephyr://command?q=…）。
    public var commandPrefill = ""
    /// 带"撤销"的提示（原型 toast：已切换至东京 03 · 撤销）。
    public var toast: UndoToast?

    /// 连接前钩子：App 层注入（启动 NEPacketTunnel、请求 VPN 授权）。抛错即中止连接。
    @ObservationIgnored public var beforeConnect: (@MainActor () async throws -> Void)?

    // MARK: 内部
    @ObservationIgnored var streamTasks: [Task<Void, Never>] = []
    @ObservationIgnored var trafficTask: Task<Void, Never>?
    @ObservationIgnored var isForeground = true
    @ObservationIgnored var started = false

    public init(engine: any ZephyrEngine, now: @escaping @Sendable () -> Int64 = { ZFormat.nowMillis() }) {
        self.engine = engine
        self.now = now
    }

    // MARK: 派生

    public var isConnected: Bool { connection.status == .connected }
    /// 开关的目标状态：连接中也显示为"开"。
    public var isOn: Bool { connection.status == .connected || connection.status == .connecting }

    /// 首页"场景"区右侧："2 小时前检测" / "正在检测…"。
    public var scenesTestedText: String? {
        if !retesting.isEmpty { return "正在检测…" }
        guard let t = scenes.compactMap(\.testedAt).max() else { return nil }
        return "\(ZFormat.relative(t, now: now()))检测"
    }

    public func scene(id: String) -> Scene? { scenes.first { $0.id == id } }
}

// MARK: - 辅助类型

/// 首页场景卡左右滑动后的待确认切换。`exit` 为 nil 表示仍在向引擎请求预览。
public struct PendingSceneChange: Hashable, Sendable {
    public var sceneId: String
    public var from: NodeSummary
    public var to: NodeSummary
    public var exit: ExitChange?
}

/// 带撤销的提示。`undo` 为 nil 时只显示文字。
public struct UndoToast: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    public var undo: (@MainActor () async -> Void)?
    public init(message: String, undo: (@MainActor () async -> Void)? = nil) {
        self.message = message; self.undo = undo
    }
    public static func == (a: UndoToast, b: UndoToast) -> Bool { a.id == b.id }
}

// AppModel 的导航与深链。

import Foundation
import ZephyrKit

extension AppModel {

    /// 打开一个浮层（会先收起指令层）。
    /// 已有另一个浮层时，不直接替换 item（SwiftUI 会边关边开，偶发闪动，REVIEW-Q1 L-P2-4）：
    /// 先收起当前浮层，记下目标，等 RootView 的 onDismiss 回调 presentPendingSheet() 再呈现。
    public func present(_ route: SheetRoute) {
        isCommandPresented = false
        if let current = sheet, current != route {
            pendingSheet = route
            sheet = nil
            return
        }
        pendingSheet = nil
        sheet = route
    }

    /// 浮层收起动画结束（RootView `.sheet(onDismiss:)`）：呈现排队中的浮层。
    public func presentPendingSheet() {
        guard sheet == nil, let next = pendingSheet else { return }
        pendingSheet = nil
        sheet = next
    }

    public func dismissSheet() {
        pendingSheet = nil
        sheet = nil
    }

    /// 推入一个页面（会先收起浮层与指令层）。L 的页面也用它互相跳转。
    public func push(_ route: Route) {
        // 从资料库 sheet 里推入的页面，返回时回到资料库；其他入口不带这个语义。
        if sheet == .library { returnsToLibrary = true }
        else if path.isEmpty { returnsToLibrary = false }
        isCommandPresented = false
        sheet = nil
        pendingSheet = nil
        path.append(route)
    }

    /// 路径回到根（用户点了返回）时，若来自资料库则重新打开它。
    public func pathDidChange() {
        guard path.isEmpty, returnsToLibrary else { return }
        returnsToLibrary = false
        if sheet == nil { sheet = .library }
    }

    public func popToHome() {
        returnsToLibrary = false
        isCommandPresented = false
        sheet = nil
        pendingSheet = nil
        path.removeAll()
    }

    /// 展开指令层（原型 07），可预填。
    public func openCommand(prefill: String = "") {
        sheet = nil
        pendingSheet = nil
        commandPrefill = prefill
        isCommandPresented = true
    }

    public func closeCommand() {
        isCommandPresented = false
        commandPrefill = ""
    }

    /// 处理 zephyr:// 深链。返回是否识别。
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        open(link, source: DeepLinkPolicy.source(of: url, trustedToken: trustedLinkToken))
        return true
    }

    /// 用户在确认弹窗里点了“确认”。
    public func confirmPendingLink() {
        guard let pending = pendingLink else { return }
        pendingLink = nil
        open(pending.link, source: .trusted)
    }

    public func open(_ link: DeepLink, source: DeepLinkSource = .trusted) {
        if DeepLinkPolicy.requiresConfirmation(link, source: source, isOn: isOn, mode: connection.mode),
           let prompt = DeepLinkPolicy.prompt(for: link, isOn: isOn) {
            popToHome()
            pendingLink = PendingDeepLink(link: link, prompt: prompt)
            return
        }
        switch link {
        case .home: popToHome()
        case .connect: Task { await connect() }
        case .disconnect: Task { await disconnect() }
        case .toggle: Task { await toggleConnection() }
        case .mode(let raw):
            if let m = ProxyMode(rawValue: raw) { Task { await setMode(m) } }
        case .sheet(let s):
            returnsToLibrary = false
            path.removeAll()
            present(s)
        case .command(let q):
            returnsToLibrary = false
            path.removeAll()
            openCommand(prefill: q)
        case .push(let r):
            popToHome()
            path.append(r)
        }
    }
}

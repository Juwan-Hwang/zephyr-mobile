// AppModel 的导航与深链。

import Foundation
import ZephyrKit

extension AppModel {

    /// 打开一个浮层（会先收起指令层）。
    public func present(_ route: SheetRoute) {
        isCommandPresented = false
        sheet = route
    }

    public func dismissSheet() { sheet = nil }

    /// 推入一个页面（会先收起浮层与指令层）。L 的页面也用它互相跳转。
    public func push(_ route: Route) {
        isCommandPresented = false
        sheet = nil
        path.append(route)
    }

    public func popToHome() {
        isCommandPresented = false
        sheet = nil
        path.removeAll()
    }

    /// 展开指令层（原型 07），可预填。
    public func openCommand(prefill: String = "") {
        sheet = nil
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
        open(link)
        return true
    }

    public func open(_ link: DeepLink) {
        switch link {
        case .home: popToHome()
        case .connect: Task { await connect() }
        case .disconnect: Task { await disconnect() }
        case .toggle: Task { await toggleConnection() }
        case .mode(let raw):
            if let m = ProxyMode(rawValue: raw) { Task { await setMode(m) } }
        case .sheet(let s):
            path.removeAll()
            present(s)
        case .command(let q):
            path.removeAll()
            openCommand(prefill: q)
        case .push(let r):
            popToHome()
            path.append(r)
        }
    }
}

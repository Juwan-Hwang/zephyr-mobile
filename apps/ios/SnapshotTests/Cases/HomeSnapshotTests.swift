// 首页（原型 03 未连接 / 04 已连接 / 12 全局模式）与根视图。
// AppModel.preview(frozen: true)：MockEngine + 9:41 冻结时钟，连接时长固定 2:14:07。

import SwiftUI
import XCTest
import ZephyrDesign
import ZephyrFeatures
import ZephyrKit

@MainActor
final class HomeSnapshotTests: XCTestCase {

    /// HomeView 需要环境里的 AppModel；强调色由 zAssertSnapshot 的 `.zAccent` 注入（与 RootView 的做法一致）。
    private func home(connected: Bool, mode: ProxyMode = .rule) -> some View {
        let model = AppModel.preview(connected: connected, mode: mode, frozen: true)
        model.start()
        return HomeView().environment(model)
    }

    func testHomeConnected() async {
        await zAssertSnapshots(named: "home-connected", variants: ZSnapshotVariant.standardPlusAccent(.green)) { _ in
            home(connected: true)
        }
    }

    func testHomeDisconnected() async {
        await zAssertSnapshots(named: "home-disconnected", variants: ZSnapshotVariant.standardPlusAccent(.orange, light: true)) { _ in
            home(connected: false)
        }
    }

    func testHomeGlobalMode() async {
        await zAssertSnapshots(named: "home-global", variants: ZSnapshotVariant.standardPlusAccent(.pink)) { _ in
            home(connected: true, mode: .global)
        }
    }

    /// RootView 是 App 实际挂载的根：NavigationStack + 浮层宿主 + 从引擎设置读强调色 / 外观。
    func testRootView() async {
        await zAssertSnapshots(named: "root", variants: [.dark, .light, .accentSample(.pink)]) { variant in
            let model = AppModel.preview(connected: true, frozen: true)
            await SnapshotFixtures.apply(accent: variant.accent, to: model.engine)
            return RootView(model: model)
        }
    }

    func testRootViewDisconnected() async {
        await zAssertSnapshots(named: "root-disconnected", variants: [.dark, .darkAX5]) { _ in
            RootView(model: AppModel.preview(connected: false, frozen: true))
        }
    }
}

// 全 App 只有首页底部悬浮条用玻璃（ZSearchBar 按钮模式 + 资料库 ZIconButton .glass，ZGlass.swift）。
// 这里只拍带它的界面，共 10 张：首页已连接 ×3、未连接 ×2、全局模式 ×1、根视图 ×2、悬浮条组件 ×2。
// 其余界面没有玻璃，iOS 18 / 26 渲染一致，由 ZephyrSnapshotTests 的 142 张基线覆盖。

import SwiftUI
import XCTest
import ZephyrDesign
import ZephyrFeatures
import ZephyrKit

@MainActor
final class GlassSnapshotTests: XCTestCase {

    private func home(connected: Bool, mode: ProxyMode = .rule) -> some View {
        let model = AppModel.preview(connected: connected, mode: mode, frozen: true)
        model.start()
        return HomeView().environment(model)
    }

    func testHomeConnected() async throws {
        try await zAssertGlassSnapshots(named: "home-connected", variants: [.dark, .light, .darkAX5]) { _ in
            home(connected: true)
        }
    }

    func testHomeDisconnected() async throws {
        try await zAssertGlassSnapshots(named: "home-disconnected", variants: [.dark, .light]) { _ in
            home(connected: false)
        }
    }

    func testHomeGlobalMode() async throws {
        try await zAssertGlassSnapshots(named: "home-global", variants: [.dark]) { _ in
            home(connected: true, mode: .global)
        }
    }

    func testRootView() async throws {
        try await zAssertGlassSnapshots(named: "root", variants: [.dark, .light]) { _ in
            RootView(model: AppModel.preview(connected: true, frozen: true))
        }
    }

    /// 悬浮条单独放在有内容的底上：玻璃折射 / 高光要有东西可透才看得出来。
    func testFloatingBar() async throws {
        try await zAssertGlassSnapshots(named: "floating-bar", variants: [.dark, .light]) { _ in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ZSearchBar(onTap: {}, libraryAction: {})
                    .padding(.horizontal, ZTokens.Space.n4)
                    .padding(.bottom, ZTokens.Space.n4)
            }
        }
    }
}

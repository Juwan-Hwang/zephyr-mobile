// Preview / 快照用的 AppModel 工厂：注入 MockEngine，时间冻结在原型的 9:41。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

extension AppModel {
    /// - Parameters:
    ///   - connected: 是否先连上（原型 04 首页）；false = 原型 03 未连接。
    ///   - mode: 连接后切到的模式（.global = 原型 12）。
    ///   - frozen: true 用 MockClock.frozen941（快照稳定），false 用实时时钟（Preview 里看曲线流动）。
    public static func preview(connected: Bool = true, mode: ProxyMode = .rule, frozen: Bool = false) -> AppModel {
        let clock: MockClock = frozen ? .frozen941 : .live
        let engine = MockEngine(seed: 0, clock: clock, startConnected: connected)
        let model = AppModel(engine: engine, now: { clock.now() })
        if mode != .rule {
            Task { @MainActor in try? await engine.setMode(mode: mode) }
        }
        return model
    }
}

/// 页面级 Preview 容器：注入 AppModel、启动订阅、深色页面底。
@MainActor
struct HPreview<Content: View>: View {
    @State var model: AppModel
    var scheme: ColorScheme = .dark
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(model)
            .task { model.start() }
            .zPageBackground()
            .preferredColorScheme(scheme)
    }
}

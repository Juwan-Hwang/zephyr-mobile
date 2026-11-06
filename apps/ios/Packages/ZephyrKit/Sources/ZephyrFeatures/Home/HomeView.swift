// 首页（原型 03/04/05/10/11/12）。单一首页：顶栏 + 状态 + 速率曲线 + 场景 + 订阅，底部浮动指令栏与资料库按钮。
//
// 性能约定：HomeView 的 body 不读取 AppModel 的任何属性（只把环境传下去），
// 每个区块是独立的小视图，各自只读自己需要的切片；1 Hz 流量只让 RateReadout / TrafficChart 重算，
// 连接时长只让 ConnectionDuration 每秒重算。

import SwiftUI
import ZephyrDesign
import ZephyrKit

public struct HomeView: View {
    @ScaledMetric(relativeTo: .body) private var dockClearance = HMetrics.dockHeight + ZTokens.Space.n8

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HomeHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeHero()
                        .padding(.top, ZTokens.Space.n4)
                    TrafficPanel()
                        .padding(.top, ZTokens.Space.n6)
                    ScenesSection()
                    SubscriptionsSection()
                }
                .padding(.bottom, dockClearance)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: ZTokens.Space.n3) {
                UndoToastHost()
                HomeDock()
            }
            .background(alignment: .bottom) {
                HomeBottomFade().frame(height: dockClearance).ignoresSafeArea(edges: .bottom)
            }
        }
        .zPageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("首页 · 已连接") {
    HPreview(model: .preview()) { HomeView() }
}

#Preview("首页 · 未连接") {
    HPreview(model: .preview(connected: false)) { HomeView() }
}

#Preview("首页 · 全局模式") {
    HPreview(model: .preview(mode: .global)) { HomeView() }
}

#Preview("首页 · 浅色") {
    HPreview(model: .preview(), scheme: .light) { HomeView() }
}

#Preview("首页 · AX5") {
    HPreview(model: .preview()) { HomeView() }
        .dynamicTypeSize(.accessibility5)
}

#Preview("首页 · 强调色 粉") {
    HPreview(model: .preview()) { HomeView() }
        .zAccent(.pink)
}

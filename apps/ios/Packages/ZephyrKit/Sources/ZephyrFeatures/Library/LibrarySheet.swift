// LibrarySheet — 资料库（原型 13）：2×2 统计卡（节点 / 订阅 / 规则 / 场景）+ 4 行
// （小组件与控制中心 / 受信任的 Wi‑Fi / 本地代理端口 / 设置）。
//
// 数字来自引擎，中文紧凑格式：1,311 万 · 214 · 1.04 亿 · 3；VoiceOver 读完整数字。
// 轻点统计卡或行 → onOpen(item)，由宿主决定 push / present（见 RouteDestination.LibraryDestination）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

@MainActor
public struct LibrarySheet: View {
    @State private var model: LibraryModel
    @State private var showsWidgets = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onOpen: (LibraryItem) -> Void

    public init(engine: any ZephyrEngine, onOpen: @escaping (LibraryItem) -> Void) {
        _model = State(initialValue: LibraryModel(engine: engine))
        self.onOpen = onOpen
    }

    public var body: some View {
        ZSheet("资料库") {
            VStack(alignment: .leading, spacing: ZTokens.Space.n6) {
                stats
                rows
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.top, ZTokens.Space.n5)
            .padding(.bottom, PageMetrics.bottomInset)
        }
        .task { await model.start() }
        .zSheet(isPresented: $showsWidgets, detents: [.medium, .large]) { WidgetsGuideSheet() }
        .pageAccent(model.settings)
    }

    // MARK: 2×2 统计

    private var columns: [GridItem] {
        let n = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: ZTokens.Layout.cardGap), count: n)
    }

    private var stats: some View {
        LazyVGrid(columns: columns, spacing: ZTokens.Layout.cardGap) {
            LibraryStatCard(value: LibraryModel.compact(model.nodeTotal),
                            spokenValue: model.nodeTotal.map(ZFormat.count), caption: "节点") { onOpen(.nodes) }
            LibraryStatCard(value: LibraryModel.compact(model.subscriptionCount),
                            spokenValue: model.subscriptionCount.map(ZFormat.count), caption: "订阅") { onOpen(.subscriptions) }
            LibraryStatCard(value: LibraryModel.compact(model.ruleTotal),
                            spokenValue: model.ruleTotal.map(ZFormat.count), caption: "规则") { onOpen(.rules) }
            LibraryStatCard(value: LibraryModel.compact(model.sceneCount),
                            spokenValue: model.sceneCount.map(ZFormat.count), caption: "场景") { onOpen(.scenes) }
        }
    }

    // MARK: 4 行

    private var rows: some View {
        ZSettingsGroup {
            Button { showsWidgets = true } label: {
                ZSettingsRow("小组件与控制中心")
            }
            .buttonStyle(ZRowButtonStyle())
            ZDivider()
            Button { onOpen(.settings) } label: {
                ZSettingsRow("受信任的 Wi‑Fi", accessory: accessory(model.trustedWifiText))
            }
            .buttonStyle(ZRowButtonStyle())
            ZDivider()
            Button { onOpen(.settings) } label: {
                ZSettingsRow("本地代理端口", accessory: accessory(model.localPortText))
            }
            .buttonStyle(ZRowButtonStyle())
            ZDivider()
            Button { onOpen(.settings) } label: {
                ZSettingsRow("设置")
            }
            .buttonStyle(ZRowButtonStyle())
        }
    }

    private func accessory(_ value: String?) -> ZSettingsAccessory {
        value.map { .valueChevron($0) } ?? .chevron
    }
}

#Preview("资料库") {
    Color.clear
        .zSheet(isPresented: .constant(true), detents: [.medium, .large]) {
            LibrarySheet(engine: MockEngine(seed: 0, clock: .frozen941)) { _ in }
        }
        .preferredColorScheme(.dark)
}

#Preview("浅色 · AX3") {
    LibrarySheet(engine: MockEngine(seed: 0, clock: .frozen941)) { _ in }
        .zAccent(.orange)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

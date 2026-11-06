// 首页主区（原型 `.hero` + `.sub`）：
//   "已连接 / 未连接" 超大字 + 连接开关
//   模式菜单（规则 / 全局 / 直连）+ 连接时长（每秒）或"3 个场景"
// 只读 connection 与 scenes.count；时长在独立的 ConnectionDuration 小视图里每秒刷新。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct HomeHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n4) {
            let layout = dynamicType.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n4))
                : AnyLayout(HStackLayout(alignment: .bottom))
            layout {
                stateText
                if !dynamicType.isAccessibilitySize { Spacer(minLength: ZTokens.Space.n4) }
                ZConnectButton(phase: model.connection.status.connectPhase) {
                    Task { await model.toggleConnection() }
                }
            }
            HStack(spacing: ZTokens.Space.n5) {
                ModeMenu()
                if model.isConnected, let since = model.connection.since {
                    ConnectionDuration(since: since)
                } else {
                    Text(verbatim: subline)
                        .zType(.footnote)
                        .foregroundStyle(subline.isEmpty ? ZTokens.Colors.textTertiary : failureTone)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, HMetrics.homeInset)
    }

    private var stateText: some View {
        ZStack(alignment: .bottomLeading) {
            Text(verbatim: statusTitle)
                .zDisplay(.title, weight: .light)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .id(statusTitle)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .opacity.combined(with: .offset(y: -10))))
        }
        .animation(ZMotion.slow, value: statusTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var statusTitle: String {
        switch model.connection.status {
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "已连接"
        case .disconnecting: "断开中"
        case .failed: "未连接"
        }
    }

    /// 未连接时的副标题：失败原因，或"3 个场景"。
    private var subline: String {
        if model.connection.status == .failed, let e = model.connection.error { return e.userMessage }
        let n = model.scenes.count
        return n > 0 ? "\(n) 个场景" : ""
    }

    private var failureTone: Color {
        model.connection.status == .failed ? ZTokens.Colors.textDanger : ZTokens.Colors.textTertiary
    }
}

/// 模式菜单：系统 Menu + Picker，三个模式。
@MainActor
private struct ModeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let binding = Binding<ProxyMode>(
            get: { model.connection.mode },
            set: { m in Task { await model.setMode(m) } })
        Menu {
            Picker(selection: binding) {
                ForEach(ProxyMode.allCases, id: \.self) { m in
                    Label(m.zhLabel, systemImage: m.zhSymbol).tag(m)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: ZTokens.Space.n1) {
                Text(verbatim: model.connection.mode.zhLabel)
                    .zType(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ZTokens.Colors.textTertiary)
            }
            .frame(minHeight: ZTokens.Layout.touchMinIos)
            .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: model.connection.mode)
        .accessibilityLabel(Text(verbatim: "代理模式"))
        .accessibilityValue(Text(verbatim: model.connection.mode.zhLabel))
    }
}

/// 连接时长：每秒刷新，只重算这一行文字。
@MainActor
struct ConnectionDuration: View {
    let since: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let ms = max(0, model.now() - since)
            Text(verbatim: ZFormat.duration(ms))
                .zType(.footnote, monospacedDigits: true)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .accessibilityLabel(Text(verbatim: "已连接 \(Self.spoken(ms))"))
        }
    }

    static func spoken(_ ms: Int64) -> String {
        let s = ms / 1000
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) 小时 \(m) 分钟" : "\(m) 分钟"
    }
}

extension ConnectionStatus {
    /// 引擎状态 → D 的 ZConnectButton 相位（失败 = 关）。
    var connectPhase: ZConnectPhase {
        switch self {
        case .disconnected, .failed: .off
        case .connecting: .connecting
        case .connected: .on
        case .disconnecting: .disconnecting
        }
    }
}

extension ProxyMode {
    /// 原型文案：规则 / 全局 / 直连。
    var zhLabel: String {
        switch self { case .rule: "规则"; case .global: "全局"; case .direct: "直连" }
    }
    var zhSymbol: String {
        switch self { case .rule: "arrow.triangle.branch"; case .global: "globe"; case .direct: "arrow.right" }
    }
}

#Preview("已连接") {
    HPreview(model: .preview()) { HomeHero() }
}

#Preview("未连接 · AX5") {
    HPreview(model: .preview(connected: false)) { HomeHero() }
        .dynamicTypeSize(.accessibility5)
}

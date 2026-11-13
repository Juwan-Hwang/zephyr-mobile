// 首页主区（原型 `.hero` + `.sub`）：
//   "已连接 / 未连接" 超大字 + 连接开关
//   模式菜单（规则 / 全局 / 直连）+ 连接时长或"3 个场景"（`.sub`：14pt、间距 14）
// 只读 connection 与 scenes.count；时长用系统计时 Text（`style: .timer`），不重算 body（REVIEW H-P2-2）。

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
            HStack(spacing: HMetrics.subGap) {
                ModeMenu()
                if model.isConnected, let since = model.connection.since {
                    ConnectionDuration(since: since)
                } else {
                    Text(verbatim: subline)
                        .hFont(HMetrics.subFont, relativeTo: .subheadline)
                        .foregroundStyle(subline.isEmpty ? ZColor.t3 : failureTone)
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
                .foregroundStyle(ZTokens.Colors.screenT1)
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
        case .disconnected: ZL.tr("未连接")
        case .connecting: ZL.tr("连接中")
        case .connected: ZL.tr("已连接")
        case .disconnecting: ZL.tr("断开中")
        case .failed: ZL.tr("未连接")
        }
    }

    /// 未连接时的副标题：失败原因，或"3 个场景"。
    private var subline: String {
        if model.connection.status == .failed, let e = model.connection.error { return e.userMessage }
        let n = model.scenes.count
        return n > 0 ? ZL.f("%lld 个场景", Int64(n)) : ""
    }

    private var failureTone: Color {
        model.connection.status == .failed ? ZTokens.Colors.screenRed : ZColor.t3
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
                    .hFont(HMetrics.subFont, relativeTo: .subheadline)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                // 原型 `.mode svg{opacity:.5}`：箭头与文字同色、半透明。
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .opacity(0.5)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: ZTokens.Layout.touchMinIos)
            .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: model.connection.mode)
        .accessibilityLabel(Text("代理模式"))
        .accessibilityValue(Text(verbatim: model.connection.mode.zhLabel))
    }
}

/// 连接时长 "2:14:07"：系统计时 Text 自己按秒走，零 body 重算，锁屏 / 后台恢复也准（REVIEW H-P2-2）。
/// Preview / 快照注入了冻结时钟（Mock 9:41）时，系统计时会按真实时间走而失真，此时退回静态文字。
@MainActor
struct ConnectionDuration: View {
    let since: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        let nowMs = model.now()
        if Self.usesSystemClock(nowMs) {
            let start = Date(timeIntervalSince1970: Double(since) / 1000)
            styled(Text(start, style: .timer))
                // VoiceOver 读取时取计时 Text 的当前值，不会过期。
                .accessibilityLabel(Text(verbatim: ZL.tr("已连接") + " ") + Text(start, style: .timer))
        } else {
            let ms = max(0, nowMs - since)
            styled(Text(verbatim: ZFormat.duration(ms)))
                .accessibilityLabel(Text("已连接 \(Self.spoken(ms))"))
        }
    }

    private func styled(_ text: Text) -> some View {
        text
            .hFont(HMetrics.subFont, relativeTo: .subheadline, monospacedDigits: true)
            .foregroundStyle(ZColor.t3)
    }

    /// 注入的时钟与系统时钟相差 5 秒以内 → 视为系统时钟。
    static func usesSystemClock(_ injectedNow: Int64) -> Bool {
        abs(injectedNow - ZFormat.nowMillis()) < 5_000
    }

    static func spoken(_ ms: Int64) -> String {
        let s = ms / 1000
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? ZL.f("%lld 小时 %lld 分钟", h, m) : ZL.f("%lld 分钟", m)
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
        switch self { case .rule: ZL.tr("规则"); case .global: ZL.tr("全局"); case .direct: ZL.tr("直连") }
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

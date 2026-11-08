// 活动（原型 08 最近连接 / 09 连接轨迹，截图 act.png / trace.png）。
//
//   刚才                                  完成
//   ┌ claude.ai          2.1 MB › ┐  ← activeConnections 按域名聚合（RecentHost）
//   │ AI，US-Fixed-01               │
//   └ …                             ┘
//   iPhone 看不到是哪个 App 发起的，只能显示域名。
// 轻点一行 → 同一 sheet 内切到连接轨迹（TraceView）；深链 zephyr://connections/<host> 直接打开轨迹。
// 长按一行：关闭该域名的全部连接（契约 §8 closeConnection）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct ActivitySheet: View {
    /// 非 nil 时直接打开该域名的轨迹（SheetRoute.connections(traceID:) 的 traceID 即域名）。
    let initialHost: String?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var connections: [ConnectionInfo] = []
    @State private var received = false
    @State private var host: String?

    /// 连接流每次推送时聚合一次并缓存（REVIEW H-P2-13），body 内不再重复聚合。
    @State private var hosts: [RecentHost] = []

    /// 标题：列表页"刚才"，轨迹页留空（轨迹自带域名大标题）。
    private var title: LocalizedStringKey {
        if host == nil { return "刚才" }
        return ""
    }

    /// 从列表进入轨迹时提供"‹ 刚才"返回；深链直达时为 nil。
    private var backAction: (@MainActor () -> Void)? {
        guard initialHost == nil else { return nil }
        return { backToList() }
    }

    private var traceTransition: AnyTransition {
        let slide: AnyTransition = AnyTransition.move(edge: .trailing).combined(with: .opacity)
        return AnyTransition.asymmetric(insertion: slide, removal: slide)
    }

    var body: some View {
        ZSheet(title) {
            content
        }
        .task { await observe() }
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .topLeading) {
            if let current = host {
                trace(for: current)
            } else {
                list.transition(AnyTransition.opacity)
            }
        }
    }

    private func trace(for current: String) -> some View {
        let key: String = current.lowercased()
        let recent: RecentHost? = hosts.first(where: { (h: RecentHost) -> Bool in h.host == key })
        return TraceView(host: current, recent: recent, onBack: backAction)
            .transition(traceTransition)
    }

    private func observe() async {
        host = initialHost
        for await latest in model.engine.activeConnections() {
            connections = latest
            hosts = RecentHost.aggregate(latest)
            received = true
        }
    }

    private var motion: Animation? { ZMotion.motion(ZMotion.page, reduceMotion: reduceMotion) }

    private func backToList() {
        withAnimation(motion) { host = nil }
    }

    private func open(_ h: RecentHost) {
        withAnimation(motion) { host = h.host }
    }

    // MARK: 列表

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            listBody
            footnote
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if hosts.isEmpty {
            emptyState
        } else {
            hostsCard
        }
    }

    private var emptyMessage: LocalizedStringKey? {
        guard received else { return nil }
        return "连接后，这里会显示刚才访问过的域名。"
    }

    private var emptyRedaction: RedactionReasons {
        received ? RedactionReasons() : RedactionReasons.placeholder
    }

    private var emptyState: some View {
        ZEmptyState("没有最近连接",
                    message: emptyMessage,
                    systemImage: "point.3.connected.trianglepath.dotted")
            .frame(maxWidth: .infinity)
            .padding(.top, ZTokens.Space.n8)
            .redacted(reason: emptyRedaction)
    }

    private var hostsCard: some View {
        let items: [RecentHost] = hosts
        return ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    hostRow(pair.element, showsDivider: pair.offset > 0)
                }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
        .padding(.top, ZTokens.Space.n5)
    }

    @ViewBuilder
    private func hostRow(_ h: RecentHost, showsDivider: Bool) -> some View {
        if showsDivider { ZDivider() }
        Button {
            open(h)
        } label: {
            RecentHostRow(item: h, sceneName: sceneName(h))
        }
        .buttonStyle(ZRowButtonStyle())
        .contextMenu { closeMenu(h) }
    }

    private func closeMenu(_ h: RecentHost) -> some View {
        Button(role: .destructive) {
            close(h)
        } label: {
            Label {
                Text(verbatim: "关闭 \(h.connections) 个连接")
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
    }

    private var footnote: some View {
        Text(verbatim: "iPhone 看不到是哪个 App 发起的，只能显示域名。")
            .zType(.caption)
            .foregroundStyle(ZTokens.Colors.screenT3)
            .padding(.horizontal, HMetrics.homeInset + ZTokens.Space.n1)
            .padding(.top, ZTokens.Space.n3)
            .padding(.bottom, ZTokens.Space.n8)
    }

    private func sceneName(_ h: RecentHost) -> String? {
        guard let id = h.scene else { return nil }
        return model.scene(id: id)?.name ?? id
    }

    private func close(_ h: RecentHost) {
        let engine = model.engine
        let ids = h.connectionIds
        Task {
            for id in ids { try? await engine.closeConnection(id: id) }
        }
    }
}

#Preview("刚才") {
    HPreview(model: .preview()) { ActivitySheet(initialHost: nil) }
}

#Preview("轨迹 · claude.ai") {
    HPreview(model: .preview()) { ActivitySheet(initialHost: "claude.ai") }
}

#Preview("刚才 · 浅色 · AX5") {
    HPreview(model: .preview(), scheme: .light) { ActivitySheet(initialHost: nil) }
        .dynamicTypeSize(.accessibility5)
}

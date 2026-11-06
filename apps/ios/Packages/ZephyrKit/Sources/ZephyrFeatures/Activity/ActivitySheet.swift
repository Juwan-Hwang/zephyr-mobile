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

    private var hosts: [RecentHost] { RecentHost.aggregate(connections) }

    var body: some View {
        ZSheet(host == nil ? "刚才" : "") {
            ZStack(alignment: .topLeading) {
                if let host {
                    TraceView(host: host,
                              recent: hosts.first { $0.host == host.lowercased() },
                              onBack: initialHost == nil ? backToList : nil)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    list.transition(.opacity)
                }
            }
        }
        .task {
            host = initialHost
            for await list in model.engine.activeConnections() {
                connections = list
                received = true
            }
        }
    }

    private var motion: Animation? { ZMotion.motion(ZMotion.page, reduceMotion: reduceMotion) }

    private func backToList() {
        withAnimation(motion) { host = nil }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hosts.isEmpty {
                ZEmptyState("没有最近连接",
                            message: received ? "连接后，这里会显示刚才访问过的域名。" : nil,
                            systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
                    .padding(.top, ZTokens.Space.n8)
                    .redacted(reason: received ? [] : .placeholder)
            } else {
                ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(hosts.enumerated()), id: \.element.id) { i, h in
                            if i > 0 { ZDivider() }
                            Button {
                                withAnimation(motion) { host = h.host }
                            } label: {
                                RecentHostRow(item: h, sceneName: sceneName(h))
                            }
                            .buttonStyle(ZRowButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) { close(h) } label: {
                                    Label { Text(verbatim: "关闭 \(h.connections) 个连接") } icon: { Image(systemName: "xmark.circle") }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, HMetrics.cardInset)
                .padding(.top, ZTokens.Space.n5)
            }
            Text(verbatim: "iPhone 看不到是哪个 App 发起的，只能显示域名。")
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .padding(.horizontal, HMetrics.homeInset + ZTokens.Space.n1)
                .padding(.top, ZTokens.Space.n3)
                .padding(.bottom, ZTokens.Space.n8)
        }
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

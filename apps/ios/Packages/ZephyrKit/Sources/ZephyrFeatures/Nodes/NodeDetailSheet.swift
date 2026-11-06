// NodeDetailSheet — 点节点行弹出的详情（服务器已脱敏、端口、订阅、协议、延迟）+ “测速”。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

struct NodeDetailSheet: View {
    let engine: any ZephyrEngine
    let node: NodeSummary
    var onTest: () -> Void
    @State private var detail: NodeDetail?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: ZTokens.Space.n3) {
                        ZFlag(node.region)
                        Text(verbatim: node.name)
                            .zType(.title)
                            .foregroundStyle(ZTokens.Colors.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, PageMetrics.titleInset)
                    .padding(.top, ZTokens.Space.n4)
                    .accessibilityElement(children: .combine)

                    ZSettingsGroup {
                        ZSettingsRow("协议", accessory: .value(node.protocol))
                        ZDivider()
                        ZSettingsRow("延迟", accessory: .value(ZFormat.latency(node.latencyMs)))
                        ZDivider()
                        ZSettingsRow("服务器", accessory: .value(detail.map { "\($0.server):\($0.port)" } ?? "—"))
                        ZDivider()
                        ZSettingsRow("订阅", accessory: .value(detail?.subscription ?? "—"))
                        if let tag = node.tag {
                            ZDivider()
                            ZSettingsRow("线路", accessory: .value([node.carrier, tag].compactMap { $0 }.joined(separator: " · ")))
                        }
                    }
                    .padding(.horizontal, PageMetrics.margin)
                    .padding(.top, ZTokens.Space.n5)
                }
            }
            .zPageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("测速") { onTest(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { detail = try? await engine.node(id: node.id) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NodeDetailSheet(engine: MockEngine(seed: 0, clock: .frozen941),
                    node: NodeSummary(id: 100_000_000, name: "东京 NTT IPLC 01", region: "JP", city: "东京",
                                      carrier: "NTT", tag: "IPLC", protocol: "VLESS", latencyMs: 76),
                    onTest: {})
}

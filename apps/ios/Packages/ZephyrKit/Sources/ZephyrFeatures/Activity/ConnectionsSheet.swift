// ConnectionsSheet —— 活动连接（契约 §8 activeConnections）。
// [A] 先补可用实现以解除编译；B 可按原型 ActivitySheet/TraceSheet 细化视觉。
//  - 订阅 engine.activeConnections()，按上下行总量降序。
//  - initialTraceID 非空时置顶高亮该连接（从指令/通知跳入"追踪这条连接"）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct ConnectionsSheet: View {
    var initialTraceID: String?
    @Environment(AppModel.self) private var model
    @State private var connections: [ConnectionInfo] = []
    @State private var query = ""

    private var shown: [ConnectionInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? connections : connections.filter {
            $0.host.lowercased().contains(q) || ($0.app?.lowercased().contains(q) ?? false) || $0.node.lowercased().contains(q)
        }
        return filtered.sorted { a, b in
            if a.id == initialTraceID { return true }
            if b.id == initialTraceID { return false }
            return a.upBytes + a.downBytes > b.upBytes + b.downBytes
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if shown.isEmpty {
                    Text(connections.isEmpty ? "暂无活动连接" : "没有匹配的连接")
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                } else {
                    ForEach(shown) { c in
                        ConnectionRow(info: c, highlighted: c.id == initialTraceID, now: model.now())
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "主机、应用或节点")
            .navigationTitle("活动连接 \(connections.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            for await list in model.engine.activeConnections() {
                connections = list
            }
        }
    }
}

private struct ConnectionRow: View {
    let info: ConnectionInfo
    let highlighted: Bool
    let now: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(info.host)
                    .font(.body.weight(highlighted ? .semibold : .regular))
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("↑\(ZFormat.bytes(info.upBytes)) ↓\(ZFormat.bytes(info.downBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ZTokens.Colors.textSecondary)
            }
            Text([info.app, info.scene, info.node, ZFormat.duration(max(0, now - info.startedAt))]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

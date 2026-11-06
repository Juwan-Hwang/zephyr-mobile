// 兼容名：X 的快照用例（SnapshotTests/Cases/ActivitySnapshotTests.swift）按旧签名 `ConnectionsSheet(initialTraceID:)` 构造。
// 实际视图是 ActivitySheet（"刚才" + 连接轨迹）；traceID 即域名。新代码请直接用 ActivitySheet。

import SwiftUI

@MainActor
struct ConnectionsSheet: View {
    var initialTraceID: String?

    var body: some View {
        ActivitySheet(initialHost: initialTraceID)
    }
}

#Preview {
    HPreview(model: .preview()) { ConnectionsSheet(initialTraceID: nil) }
}

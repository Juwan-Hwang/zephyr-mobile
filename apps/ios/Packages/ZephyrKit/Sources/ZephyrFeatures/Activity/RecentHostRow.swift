// "刚才"列表行（原型 `.act .li`）：域名 + "AI，US-Fixed-01" / "直连"，右侧等宽流量 + ›。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct RecentHostRow: View {
    let item: RecentHost
    /// 场景显示名；nil = 直连。
    let sceneName: String?

    private var subtitle: String {
        guard !item.isDirect, let sceneName else { return ZL.tr("直连") }
        return ZL.s("%@，%@", sceneName, item.node)
    }

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                Text(verbatim: item.host)
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .zType(.caption)
                    .foregroundStyle(ZTokens.Colors.screenT3)
                    .lineLimit(1)
            }
            Spacer(minLength: ZTokens.Space.n3)
            Text(verbatim: ZFormat.bytes(item.totalBytes))
                .zMono(.body)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .fixedSize()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ZQuaternaryText())
                .accessibilityHidden(true)
        }
        .padding(.vertical, ZTokens.Space.n4)
        .padding(.horizontal, ZTokens.Space.n5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.host)，\(subtitle)，\(ZFormat.bytes(item.totalBytes))"))
        .accessibilityHint(Text("轻点两下查看连接轨迹"))
    }
}

#Preview {
    VStack(spacing: 0) {
        RecentHostRow(item: RecentHost(host: "claude.ai", scene: "ai", node: "US-Fixed-01", connections: 17,
                                       totalBytes: 2_100_000, lastSeenAt: 0, connectionIds: []), sceneName: "AI")
        RecentHostRow(item: RecentHost(host: "qq.com", scene: nil, node: "DIRECT", connections: 3,
                                       totalBytes: 3_400_000, lastSeenAt: 0, connectionIds: []), sceneName: nil)
    }
    .zPageBackground()
}

// 空状态（原型 `.vempty`：居中，标题 17 t1，说明 14 t3；可选图标与按钮）。
// 节点搜索无结果、没有订阅、没有最近连接。

import SwiftUI

public struct ZEmptyState: View {
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let systemImage: String?
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    public init(_ title: LocalizedStringKey,
                message: LocalizedStringKey? = nil,
                systemImage: String? = nil,
                actionTitle: LocalizedStringKey? = nil,
                action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: ZTokens.Space.n2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .fontWeight(.ultraLight)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .padding(.bottom, ZTokens.Space.n3)
                    .accessibilityHidden(true)
            }
            Text(title)
                .zType(.headline)
                .fontWeight(.regular)
                .foregroundStyle(ZTokens.Colors.textPrimary)
            if let message {
                Text(message)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
            }
            if let actionTitle, let action {
                ZButton(actionTitle, kind: .ghost, action: action)
                    .padding(.top, ZTokens.Space.n4)
            }
        }
        .multilineTextAlignment(.center)
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private struct ZEmptySample: View {
    var body: some View {
        ZEmptyState("没有匹配的节点", message: "试试地区、协议或倍率，如 “JP 0.5x”")
        ZEmptyState("还没有订阅", message: "粘贴链接、扫码或从电脑导入", systemImage: "tray", actionTitle: "添加订阅") {}
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZEmptySample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZEmptySample() } }
#Preview("强调色") { ZAccentMatrix { ZEmptyState("没有最近连接", systemImage: "point.3.connected.trianglepath.dotted") } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZEmptySample() } }

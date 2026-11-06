// 1px 分隔线（原型 `.row+.row{border-top:1px solid var(--hl)}`），可左缩进（节点行 left:22px）。

import SwiftUI

public struct ZDivider: View {
    private let leadingInset: CGFloat

    public init(leadingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
    }

    public var body: some View {
        Rectangle()
            .fill(ZTokens.Colors.borderSubtle)
            .frame(height: ZMetrics.hairline)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

#Preview("深色") {
    ZPreviewCanvas {
        ZCard(padding: 0) {
            VStack(spacing: 0) {
                Text(verbatim: "视频").padding()
                ZDivider()
                Text(verbatim: "其他").padding()
                ZDivider(leadingInset: ZTokens.Space.n5)
                Text(verbatim: "缩进").padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("浅色") {
    ZPreviewCanvas(scheme: .light) {
        ZCard(padding: 0) {
            VStack(spacing: 0) {
                Text(verbatim: "视频").padding()
                ZDivider()
                Text(verbatim: "其他").padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

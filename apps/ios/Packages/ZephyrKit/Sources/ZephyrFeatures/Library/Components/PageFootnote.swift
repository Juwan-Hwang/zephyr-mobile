// PageFootnote — 分组下方的说明文字（原型 .ft：13pt 三级色，左缩进与页头标题对齐）。

import SwiftUI
import ZephyrDesign

struct PageFootnote: View {
    private let text: Text
    private let centered: Bool

    init(_ key: LocalizedStringKey, centered: Bool = false) {
        text = Text(key); self.centered = centered
    }

    init(verbatim s: String, centered: Bool = false) {
        text = Text(verbatim: s); self.centered = centered
    }

    var body: some View {
        text
            .zType(.footnote)
            .foregroundStyle(ZTokens.Colors.textTertiary)
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PageMetrics.titleInset)
            .padding(.top, ZTokens.Space.n3)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

#Preview {
    PageFootnote("规则集在设备上编译为只读索引，按需从磁盘读取。订阅更新时，覆写保持不变。")
        .zPageBackground()
        .preferredColorScheme(.dark)
}

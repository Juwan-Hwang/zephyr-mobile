// LibraryStatCard — 资料库 2×2 统计卡（原型 .lc：30pt 细字数字 + 13pt 说明，整卡可点）。

import SwiftUI
import ZephyrDesign

struct LibraryStatCard: View {
    /// 紧凑显示值（“1,311 万”）；nil = 加载中。
    var value: String?
    /// 朗读用完整值（“13,109,802”）。
    var spokenValue: String?
    var caption: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZCard(padding: ZTokens.Space.n5, cornerRadius: ZTokens.Radius.overlay - ZTokens.Space.n1) {
                ZBigNumber(value ?? "000", size: .small, caption: caption,
                           accessibilityLabel: spokenValue.map { Text(caption) + Text(verbatim: " \($0)") })
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .redacted(reason: value == nil ? .placeholder : [])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(ZPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(verbatim: "打开"))
    }
}

#Preview {
    HStack(spacing: ZTokens.Layout.cardGap) {
        LibraryStatCard(value: "1,311 万", spokenValue: "13,109,802", caption: "节点") {}
        LibraryStatCard(value: nil, caption: "订阅") {}
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}

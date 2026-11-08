// LibraryStatCard — 资料库 2×2 统计卡（原型 .lc：高 110、细字数字在顶 + 14pt t2 说明在底，整卡可点）。

import SwiftUI
import ZephyrDesign

struct LibraryStatCard: View {
    /// 紧凑显示值（“1,311 万”）；nil = 加载中。
    var value: String?
    /// 朗读用完整值（“13,109,802”）。
    var spokenValue: String?
    var caption: LocalizedStringKey
    var action: () -> Void

    /// 110 − 上下内边距 2×20；是最小值，大字体下随内容增高。
    static let minContentHeight: CGFloat = 70

    var body: some View {
        Button(action: action) {
            // 原型 .lc：固定高 110（AX 尺寸随内容增高）、数字在顶、说明在底（space-between），说明 14 t2（REVIEW L-P1-2）。
            ZCard(padding: ZTokens.Space.n5, cornerRadius: ZTokens.Radius.overlay - ZTokens.Space.n1) {
                VStack(alignment: .leading, spacing: 0) {
                    ZBigNumber(value ?? "000", size: .small,
                               accessibilityLabel: Text(caption) + Text(verbatim: " \(spokenValue ?? value ?? "")"))
                        .foregroundStyle(ZTokens.Colors.screenT1)
                        .redacted(reason: value == nil ? .placeholder : [])
                    Spacer(minLength: ZTokens.Space.n3)
                    Text(caption)
                        .zType(.footnote)
                        .foregroundStyle(ZColor.t2)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: Self.minContentHeight, alignment: .topLeading)
            }
        }
        .buttonStyle(ZPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("打开"))
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

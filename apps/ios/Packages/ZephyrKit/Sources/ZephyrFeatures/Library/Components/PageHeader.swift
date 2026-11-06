// PageHeader — 资料库类页面的页头（原型 .pgh）：大标题 → 细字大数字 + 单位 → 副标题。
//
//   订阅
//   214  个 · 每 12 小时更新
//
// 大数字用 ZBigNumber（.title = 44pt 细字、等宽数字）；number 为 nil 时显示占位并 redacted。

import SwiftUI
import ZephyrDesign

struct PageHeader: View {
    var title: LocalizedStringKey
    /// 已格式化的数字（ZFormat.count）；nil = 加载中；不传 = 不显示数字行（设置页）。
    var number: String?
    var unit: String?
    var subtitle: String?
    var showsNumber = true
    /// 左右内边距；放在 List 行里（已有列表边距）时传 ZTokens.Space.n2。
    var horizontalInset: CGFloat = PageMetrics.titleInset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .zType(.large)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if showsNumber {
                ZBigNumber(number ?? "000", unit: unit, size: .title)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .redacted(reason: number == nil ? .placeholder : [])
                    .padding(.top, ZTokens.Space.n4)
            }
            if let subtitle {
                Text(verbatim: subtitle)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .padding(.top, ZTokens.Space.n1)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, ZTokens.Space.n2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack {
        PageHeader(title: "订阅", number: "214", unit: "个 · 每 12 小时更新")
        PageHeader(title: "规则", number: nil, unit: "条", subtitle: "7 层 · 已编译 · 磁盘占用 1.9 GB")
        PageHeader(title: "设置", showsNumber: false)
    }
    .zPageBackground()
    .preferredColorScheme(.dark)
}

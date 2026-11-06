// LPageHeader — 资料库类页面的页头（原型 .pgh）：标题 → 细字大数字 + 单位 → 副标题。
//
//   节点
//   13,109,802 个
//   来自 214 个订阅 · 15 个地区

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct LPageHeader: View {
    var title: String
    /// nil = 还在加载（显示占位）
    var number: Int64?
    var unit: String?
    var subtitle: String?
    /// 大数字后单位的补充说明（订阅页：“个 · 每 12 小时更新”整体作为 unit）
    var numberLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .zType(.large)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if number != nil || unit != nil {
                HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                    Text(number.map(ZFormat.count) ?? "0,000,000")
                        .zType(.metric)
                        .foregroundStyle(ZTokens.Colors.textPrimary)
                        .contentTransition(.numericText())
                        .redacted(reason: number == nil ? .placeholder : [])
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let unit {
                        Text(unit)
                            .zType(.footnote)
                            .foregroundStyle(ZTokens.Colors.textTertiary)
                    }
                }
                .padding(.top, ZTokens.Space.n4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(numberLabel ?? "\(number.map(ZFormat.count) ?? "正在载入") \(unit ?? "")")
            }
            if let subtitle {
                Text(subtitle)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .padding(.top, ZTokens.Space.n1)
            }
        }
        .padding(.horizontal, LStyle.titleInset)
        .padding(.top, ZTokens.Space.n2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LPageHeader(title: "节点", number: 13_109_802, unit: "个", subtitle: "来自 214 个订阅 · 15 个地区")
        .background(LStyle.pageBackground)
}

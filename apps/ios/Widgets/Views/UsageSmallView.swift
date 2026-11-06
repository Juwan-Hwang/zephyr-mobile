// 小号主屏小组件：今日用量大数字 + 24 小时柱状图（原型 shots/hs.png 右上）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct UsageSmallView: View {
    var state: SharedState
    var now: Date

    var body: some View {
        let usage = state.usage(on: now)
        let parts = ZFormat.bytesParts(usage.todayBytes)
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            Text("今日")
                .zType(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(ZTokens.Colors.textSecondary)
            HStack(alignment: .lastTextBaseline, spacing: ZTokens.Space.n1) {
                Text(parts.value)
                    .zType(.metric)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(parts.unit)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("今日用量 \(ZFormat.bytes(usage.todayBytes))")
            UsageBars(hourly: usage.hourly, accent: WidgetStyle.accent(state.accent))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("0 时")
                Spacer(minLength: ZTokens.Space.n1)
                Text("现在")
            }
            .zType(.caption)
            .foregroundStyle(ZTokens.Colors.textTertiary)
            .accessibilityHidden(true)
        }
        .dynamicTypeSize(...WidgetStyle.maxDynamicType)
    }
}

#Preview {
    UsageSmallView(state: .prototype(), now: Date())
        .padding(ZTokens.Space.n5)
        .frame(width: 170, height: 170)
        .background(ZTokens.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
}

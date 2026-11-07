// 小号主屏小组件：标志 + 电源按钮，下方大数字速率与 “MB/s · 规则”（原型 shots/hs.png 左上）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct StatusSmallView: View {
    var state: SharedState

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n0) {
            HStack(alignment: .top) {
                WidgetMark()
                    .frame(height: ZTokens.Space.n5)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                Spacer(minLength: ZTokens.Space.n3)
                PowerButton(isOn: state.connection.isOn)
            }
            Spacer(minLength: ZTokens.Space.n3)
            RateBlock(state: state)
        }
        .dynamicTypeSize(...WidgetStyle.maxDynamicType)
    }
}

/// 速率大数字 + 单位 · 模式；未连接时显示状态文案。
struct RateBlock: View {
    var state: SharedState

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            if state.connection.status == .connected {
                let rate = ZFormat.rate(state.rate.downBps)
                Text(rate.value)
                    .zType(.metric)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text("\(rate.unit) · \(state.connection.mode.title)")
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.screenT2)
                    .lineLimit(1)
                // 速率是上次时间线生成时的瞬时值（最长约 15 分钟前），标出它的年龄（REVIEW W-P1-2）。
                if let at = state.rate.at {
                    (Text(at, style: .relative) + Text("前"))
                        .font(.caption2)
                        .foregroundStyle(ZTokens.Colors.screenT3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text(state.connection.status.title)
                    .zType(.title)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(state.connection.status == .failed ? "轻点查看原因" : "轻点电源连接")
                    .zType(.footnote)
                    .foregroundStyle(state.connection.status == .failed ? ZTokens.Colors.screenAmber : ZTokens.Colors.screenT2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard state.connection.status == .connected else { return "Zephyr \(state.connection.status.title)" }
        return "Zephyr 已连接，\(state.connection.mode.title)模式，下行 \(ZFormat.rateString(state.rate.downBps))"
    }
}

#Preview {
    StatusSmallView(state: .prototype())
        .padding(ZTokens.Space.n5)
        .frame(width: 170, height: 170)
        .background(ZTokens.Colors.screenS1)
        .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
}

// 灵动岛（原型 shots/hs.png 顶部：紧凑态 [Z] …… 2.8 ↓）。
//   compactLeading：强调色标志；compactTrailing：下行速率；minimal：标志；
//   expanded：标志 + Zephyr / 计时器 / 速率 + 场景徽标。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct IslandCompactLeading: View {
    var accent: Color
    var body: some View {
        WidgetMark()
            .frame(height: ZTokens.Space.n4)
            .foregroundStyle(accent)
            .padding(.leading, ZTokens.Space.n1)
    }
}

struct IslandCompactTrailing: View {
    var state: ZephyrActivityAttributes.ContentState
    var isStale: Bool = false
    var body: some View {
        // 紧凑区系统建议 ≤ 15pt；过期时不显示陈旧速率。
        Text(isStale ? "—" : "\(ZFormat.rate(state.downBps).value) ↓")
            .zType(.footnote, monospacedDigits: true)
            .fontDesign(.monospaced)
            .foregroundStyle(ZTokens.Colors.screenT1)
            .contentTransition(.numericText())
            .accessibilityLabel(isStale ? String(localized: "速率已暂停更新") : String(localized: "下行 \(ZFormat.rateString(state.downBps))"))
    }
}

struct IslandMinimal: View {
    var accent: Color
    var body: some View {
        WidgetMark()
            .frame(height: ZTokens.Space.n4)
            .foregroundStyle(accent)
    }
}

/// 展开态底部区域（leading / trailing 区域由 ZephyrLiveActivity 用 IslandCompact* 与 ConnectionTimer 组合）。
struct IslandExpandedBottom: View {
    var state: ZephyrActivityAttributes.ContentState
    var isStale: Bool = false

    var body: some View {
        let down = ZFormat.rate(state.downBps)
        VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
            if isStale {
                StaleRateLine()
            } else {
            HStack(alignment: .lastTextBaseline, spacing: ZTokens.Space.n3) {
                Text(down.value)
                    .zType(.metric)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("\(down.unit) ↓")
                    .zType(.body)
                    .foregroundStyle(ZColor.t2)
                Spacer(minLength: ZTokens.Space.n3)
                Text("\(ZFormat.rateString(state.upBps)) ↑")
                    .zType(.footnote, monospacedDigits: true)
                    .foregroundStyle(ZColor.t2)
            }
            .minimumScaleFactor(0.7)
            }
            SceneChips(scenes: state.scenes)
        }
        .foregroundStyle(ZTokens.Colors.screenT1)
    }
}

#Preview {
    let state = ZephyrActivityAttributes.ContentState.prototype()
    return VStack(spacing: ZTokens.Space.n5) {
        HStack {
            IslandCompactLeading(accent: ZTokens.Accent.blue.color)
            Spacer()
            IslandCompactTrailing(state: state)
        }
        .padding(ZTokens.Space.n3)
        .frame(width: 250)
        .background(Capsule().fill(.black))
        IslandExpandedBottom(state: state)
            .padding()
            .background(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay).fill(.black))
    }
    .padding()
    .environment(\.colorScheme, .dark)
}

// 中号主屏小组件：左侧速率与开关，右侧今日用量。

import SwiftUI
import ZephyrDesign

struct StatusMediumView: View {
    var state: SharedState
    var now: Date

    var body: some View {
        HStack(spacing: ZTokens.Space.n5) {
            StatusSmallView(state: state)
            Rectangle()
                .fill(ZTokens.Colors.screenHl)
                .frame(width: 1)
                .accessibilityHidden(true)
            UsageSmallView(state: state, now: now)
        }
    }
}

#Preview {
    StatusMediumView(state: .prototype(), now: Date())
        .padding(ZTokens.Space.n5)
        .frame(width: 364, height: 170)
        .background(ZTokens.Colors.screenS1)
        .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
}

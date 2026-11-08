// 锁屏小组件 accessoryInline（日期上方一行）：“⚡︎ 2.8 MB/s · 规则”。系统只渲染一个 Text + 图标。

import SwiftUI
import ZephyrKit

struct LockInlineView: View {
    var state: SharedState

    var body: some View {
        if state.connection.status == .connected {
            Label("\(ZFormat.rateString(state.rate.downBps)) · \(state.connection.mode.displayTitle)",
                  systemImage: "bolt.horizontal.fill")
        } else {
            Label("Zephyr \(state.connection.status.displayTitle)", systemImage: "bolt.horizontal")
        }
    }
}

#Preview {
    LockInlineView(state: .prototype())
        .padding()
        .background(.black)
        .foregroundStyle(.white)
}

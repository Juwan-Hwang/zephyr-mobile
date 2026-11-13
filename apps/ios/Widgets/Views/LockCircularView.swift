// 锁屏小组件 accessoryCircular：速率环（原型 shots/lock.png 左侧 “2.8 MB/s”）。
// 环的填充按对数刻度：0 → 100 MB/s 映射到 0 → 1，常见 1–10 MB/s 落在中段。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct LockCircularView: View {
    var state: SharedState

    static func fraction(_ bps: Int64) -> Double {
        guard bps > 0 else { return 0 }
        return min(1, log10(1 + Double(bps) / 100_000) / 3)
    }

    var body: some View {
        let on = state.connection.status == .connected
        let rate = ZFormat.rate(on ? state.rate.downBps : 0)
        // 原型 shots/lock.png：容量环（无指示点），环内只有数值 + 单位；底部不放“下行”标签（76pt 下会与单位重叠），读屏文案已含“下行”。
        Gauge(value: Self.fraction(on ? state.rate.downBps : 0)) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: ZTokens.Space.n0) {
                Text(verbatim: on ? rate.value : "—")
                    .zType(.headline, monospacedDigits: true)
                    .minimumScaleFactor(0.5)
                (on ? Text(verbatim: rate.unit) : Text("未连接"))
                    .zType(.caption)
                    .minimumScaleFactor(0.5)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(on ? String(localized: "Zephyr 下行 \(ZFormat.rateString(state.rate.downBps))") : String(localized: "Zephyr 未连接"))
    }
}

#Preview {
    LockCircularView(state: .prototype())
        .frame(width: 76, height: 76)
        .padding()
        .background(.black)
        .environment(\.colorScheme, .dark)
}

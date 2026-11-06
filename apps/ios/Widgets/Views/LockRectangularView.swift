// 锁屏小组件 accessoryRectangular：“Zephyr / AI 东京 03 / 视频 香港 HKT”（原型 shots/lock.png）。

import SwiftUI
import WidgetKit
import ZephyrDesign

struct LockRectangularView: View {
    var state: SharedState

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n0) {
            Text("Zephyr")
                .zType(.headline)
                .widgetAccentable()
            if state.connection.status == .connected, !state.scenes.isEmpty {
                ForEach(state.scenes.prefix(2)) { scene in
                    Text("\(scene.name) \(scene.nodeName)")
                        .zType(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(state.connection.status.title)
                    .zType(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LockRectangularView(state: .prototype())
        .frame(width: 172, height: 76)
        .padding()
        .background(.black)
        .foregroundStyle(.white)
}

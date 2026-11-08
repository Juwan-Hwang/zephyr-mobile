// 控制中心 / 锁屏 / 操作按钮的开关（iOS 18 ControlWidget）。绑定 ConnectIntent（SetValueIntent<Bool>）。
// 只在 iOS 18+ 编译进 WidgetBundle（见 ZephyrWidgetsBundle 的 #available）。
// REVIEW-Q1 W-P2-5：开关色跟随用户强调色（SharedState.accent），不再固定蓝色。
// 值类型带上强调色：ControlCenter.shared.reloadControls / App 写 SharedState 后刷新时一起更新。

import AppIntents
import SwiftUI
import WidgetKit
import ZephyrDesign

@available(iOS 18.0, *)
struct ZephyrConnectionControl: ControlWidget {
    static let kind = WidgetKinds.connectionControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle("Zephyr", isOn: value.isOn, action: ConnectIntent()) { on in
                Label(on ? "已连接" : "未连接", systemImage: on ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
            }
            .tint(WidgetStyle.accent(value.accent))
        }
        .displayName("Zephyr")
        .description("连接或断开 Zephyr 代理。")
    }

    struct Value: Sendable, Hashable {
        var isOn: Bool
        /// blue | green | orange | pink（ZTokens.Accent rawValue）。
        var accent: String
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value { Value(isOn: false, accent: ZTokens.Accent.blue.rawValue) }

        func currentValue() async throws -> Value {
            let state = SharedStore.shared.read()
            return Value(isOn: state.connection.isOn, accent: state.accent)
        }
    }
}

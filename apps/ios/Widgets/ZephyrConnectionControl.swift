// 控制中心 / 锁屏 / 操作按钮的开关（iOS 18 ControlWidget）。绑定 ConnectIntent（SetValueIntent<Bool>）。
// 只在 iOS 18+ 编译进 WidgetBundle（见 ZephyrWidgetsBundle 的 #available）。

import AppIntents
import SwiftUI
import WidgetKit
import ZephyrDesign

@available(iOS 18.0, *)
struct ZephyrConnectionControl: ControlWidget {
    static let kind = WidgetKinds.connectionControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle("Zephyr", isOn: isOn, action: ConnectIntent()) { on in
                Label(on ? "已连接" : "未连接", systemImage: on ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
            }
            .tint(ZTokens.Accent.blue.color)
        }
        .displayName("Zephyr")
        .description("连接或断开 Zephyr 代理。")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            SharedStore.shared.read().connection.isOn
        }
    }
}

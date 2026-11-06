// MenuPickerRow — 设置类“值 ›”行：轻点弹出系统菜单单选（自动更新间隔、结果保留、外观）。
// 外观完全由 ZSettingsRow 决定；Menu 只负责弹出。

import SwiftUI
import ZephyrDesign

struct MenuOption<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var id: Value { value }
}

struct MenuPickerRow<Value: Hashable>: View {
    var title: LocalizedStringKey
    var subtitle: String?
    var options: [MenuOption<Value>]
    @Binding var selection: Value

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options) { o in Text(verbatim: o.title).tag(o.value) }
            } label: {
                Text(title)
            }
        } label: {
            ZSettingsRow(title, subtitle: subtitle, accessory: .valueChevron(current))
        }
        .menuStyle(.button)
        .buttonStyle(ZRowButtonStyle())
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityValue(Text(verbatim: current))
    }

    private var current: String {
        options.first { $0.value == selection }?.title ?? "—"
    }
}

#Preview {
    @Previewable @State var hours: Int32 = 12
    ZSettingsGroup("更新") {
        MenuPickerRow(title: "自动更新", options: [6, 12, 24].map { MenuOption(value: Int32($0), title: "每 \($0) 小时") },
                      selection: $hours)
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}

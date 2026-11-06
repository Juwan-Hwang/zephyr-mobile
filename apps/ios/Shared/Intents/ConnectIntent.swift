// ConnectIntent —— “连接 Zephyr”。
//
// 是 SetValueIntent<Bool>：控制中心开关（iOS 18 ControlWidgetToggle）与小组件电源按钮绑定它（value = 目标状态）；
// 在快捷指令里直接运行时 value 默认 true，即“连接”。断开另有 DisconnectIntent，便于 Siri 短语。

import AppIntents

struct ConnectIntent: SetValueIntent {
    static let title: LocalizedStringResource = "连接 Zephyr"
    static let description = IntentDescription("连接或断开 Zephyr 代理。", categoryName: "连接")
    static let isDiscoverable = true

    @Parameter(title: "连接", default: true)
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    static var parameterSummary: some ParameterSummary {
        Summary("连接 Zephyr：\(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ConnectionControl.resolve().setConnected(value)
        return .result()
    }
}

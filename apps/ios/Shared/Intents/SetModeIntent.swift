// SetModeIntent —— 切换代理模式（规则 / 全局 / 直连）。

import AppIntents

struct SetModeIntent: AppIntent {
    static let title: LocalizedStringResource = "切换代理模式"
    static let description = IntentDescription("在规则、全局、直连之间切换 Zephyr 的代理模式。", categoryName: "连接")
    static let isDiscoverable = true

    @Parameter(title: "模式", default: .rule)
    var mode: ZephyrModeOption

    init() {}

    init(mode: ZephyrModeOption) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("把 Zephyr 切换到 \(\.$mode) 模式")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ConnectionControl.resolve().setMode(mode.sharedMode)
        return .result(dialog: "已切换到\(mode.sharedMode.title)模式")
    }
}

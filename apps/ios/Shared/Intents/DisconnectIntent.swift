// DisconnectIntent —— “断开 Zephyr”。

import AppIntents

struct DisconnectIntent: AppIntent {
    static let title: LocalizedStringResource = "断开 Zephyr"
    static let description = IntentDescription("断开 Zephyr 代理。", categoryName: "连接")
    static let isDiscoverable = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ConnectionControl.resolve().setConnected(false)
        return .result()
    }
}

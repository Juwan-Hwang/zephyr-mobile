// 快捷指令 / Siri / Spotlight 的 App Shortcuts（只能在 App target 声明）。

import AppIntents

struct ZephyrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectIntent(),
            phrases: [
                "连接 \(.applicationName)",
                "打开 \(.applicationName)",
                "用 \(.applicationName) 连接",
            ],
            shortTitle: "连接",
            systemImageName: "bolt.horizontal.circle"
        )
        AppShortcut(
            intent: DisconnectIntent(),
            phrases: [
                "断开 \(.applicationName)",
                "关闭 \(.applicationName)",
            ],
            shortTitle: "断开",
            systemImageName: "bolt.horizontal.circle.fill"
        )
        AppShortcut(
            intent: SetModeIntent(),
            phrases: [
                "把 \(.applicationName) 切换到\(\.$mode)",
                "\(.applicationName) 切换到\(\.$mode)模式",
            ],
            shortTitle: "切换模式",
            systemImageName: "arrow.triangle.branch"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}

// LAccentModifier — 页面级强调色：订阅引擎 settings().accent，下发为 `.tint`。

import SwiftUI
import ZephyrDesign
import ZephyrKit

/// 订阅 settings() 的 accent → `.tint`。页面单独预览时也能看到正确强调色。
struct LAccentModifier: ViewModifier {
    let engine: any ZephyrEngine
    @State private var accent: ZTokens.Accent = .blue

    func body(content: Content) -> some View {
        content
            .tint(accent.color)
            .task {
                for await s in engine.settings() {
                    let a = ZTokens.Accent(rawValue: s.accent.rawValue) ?? .blue
                    if a != accent { accent = a }
                }
            }
    }
}

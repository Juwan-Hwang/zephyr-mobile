// PageAccent — 页面自带的强调色：读引擎 Settings.accent → `.zAccent(_:)`（同时设置 tint）。
// App 内 RootView 已统一注入强调色；页面单独呈现时（Preview、快照测试、App Intents 打开的独立页面）也要正确。
// 设置还没到时沿用继承下来的强调色，避免先闪蓝色。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct PageAccentModifier: ViewModifier {
    let accent: Accent?
    @Environment(\.zAccent) private var inherited

    func body(content: Content) -> some View {
        content.zAccent(accent.flatMap { ZTokens.Accent(rawValue: $0.rawValue) } ?? inherited)
    }
}

/// 没有现成 Settings 的页面：自己订阅 settings() 只取 accent。
struct EngineAccentModifier: ViewModifier {
    let engine: any ZephyrEngine
    @State private var accent: Accent?

    func body(content: Content) -> some View {
        content
            .modifier(PageAccentModifier(accent: accent))
            .task {
                for await s in engine.settings() where s.accent != accent { accent = s.accent }
            }
    }
}

extension View {
    func pageAccent(_ settings: Settings?) -> some View {
        modifier(PageAccentModifier(accent: settings?.accent))
    }

    func pageAccent(engine: any ZephyrEngine) -> some View {
        modifier(EngineAccentModifier(engine: engine))
    }
}

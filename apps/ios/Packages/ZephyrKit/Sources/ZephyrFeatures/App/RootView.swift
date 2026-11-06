// 根视图：NavigationStack（首页 + L 的页面）+ 浮层 sheet + 全屏指令层 + 错误提示。
// App target 只需：`RootView(model: AppModel(engine: …))`，并在 `beforeConnect` 里启动 NE。
//
// body 只读导航相关属性（path / sheet / isCommandPresented / settings / lastError），不读流量。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

@MainActor
public struct RootView: View {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
        .sheet(item: $model.sheet) { route in
            SheetHost(route: route, accent: accent)
        }
        .overlay {
            if model.isCommandPresented {
                CommandView(prefill: model.commandPrefill)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .top) { ErrorBanner() }
        .animation(ZMotion.slow, value: model.isCommandPresented)
        .environment(model)
        .zAccent(accent)
        .preferredColorScheme(colorScheme)
        .task { model.start() }
        .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
        .onOpenURL { model.handle(url: $0) }
    }

    private var accent: ZTokens.Accent {
        ZTokens.Accent(rawValue: model.settings?.accent.rawValue ?? "blue") ?? .blue
    }

    private var colorScheme: ColorScheme? {
        switch model.settings?.appearance {
        case .dark: .dark
        case .light: .light
        default: nil
        }
    }
}

/// 把 SheetRoute 换成具体浮层。H 的浮层自己画 D 的 ZSheet（抓手 + 标题 + 完成），这里用 `.zSheetPresentation`
/// 隐藏系统抓手；资料库（L）沿用系统抓手 + 中/大两档。sheet 内容重新注入强调色（sheet 不一定继承自定义环境值）。
@MainActor
struct SheetHost: View {
    let route: SheetRoute
    /// RootView 按设置算出的强调色（sheet 内不依赖继承）。
    let accent: ZTokens.Accent

    var body: some View {
        content
            .zAccent(accent)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .library:
            LibraryDestination()
                .zSheetPresentation(detents: [.medium, .large])
        case .scene(let id):
            SceneSheet(sceneId: id)
                .zSheetPresentation()
        case .connections(let host):
            ActivitySheet(initialHost: host)
                .zSheetPresentation()
        case .today:
            TodayCardView()
                .zSheetPresentation()
        }
    }
}

/// 引擎错误：顶部短暂横幅，3 秒后消失。
@MainActor
private struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let e = model.lastError {
                Text(verbatim: e.userMessage)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .padding(.horizontal, ZTokens.Space.n5)
                    .padding(.vertical, ZTokens.Space.n3)
                    .zSurface(.elevated, cornerRadius: ZTokens.Radius.full)
                    .padding(.top, ZTokens.Space.n3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: e) {
                        HHaptics.warning()
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if model.lastError == e { model.lastError = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
                    .onAppear { UIAccessibility.post(notification: .announcement, argument: e.userMessage) }
            }
        }
        .animation(ZMotion.slow, value: model.lastError)
    }
}

#Preview("Root") {
    RootView(model: .preview())
}

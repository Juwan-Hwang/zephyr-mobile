// 强调色环境值：ZAccentKey + EnvironmentValues.zAccent + .zAccent(_:)
// 所有 Z* 组件里的“强调色”都从这里取，不直接写 ZTokens.Accent.blue。

import SwiftUI

/// 当前强调色（默认 blue，对应主仓库 #007AFF）。
public struct ZAccentKey: EnvironmentKey {
    public static let defaultValue: ZTokens.Accent = .blue
}

public extension EnvironmentValues {
    /// 当前强调色。用 `.zAccent(_:)` 设置。
    var zAccent: ZTokens.Accent {
        get { self[ZAccentKey.self] }
        set { self[ZAccentKey.self] = newValue }
    }
}

public extension View {
    /// 为子树设置强调色；同时设置 `.tint`，让系统控件（Toggle、ProgressView、TextField 光标）一并跟随。
    func zAccent(_ accent: ZTokens.Accent) -> some View {
        environment(\.zAccent, accent)
            .tint(accent.color)
    }
}

/// 解析为当前环境强调色的 ShapeStyle：`.foregroundStyle(ZAccentStyle())`、`.fill(ZAccentStyle())`。
public struct ZAccentStyle: ShapeStyle, Sendable {
    /// 0...1，强调色的不透明度（例如命中行底色用 0.09）。
    public var opacity: Double
    public init(opacity: Double = 1) { self.opacity = opacity }
    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.zAccent.color.opacity(opacity)
    }
}

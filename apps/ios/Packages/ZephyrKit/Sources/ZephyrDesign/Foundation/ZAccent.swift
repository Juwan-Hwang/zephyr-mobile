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
    /// 为子树设置强调色；同时设置 `.tint`，让系统控件（菜单 / 工具栏图标、链接、TextField 光标）一并跟随。
    /// tint 用 accent.text：系统拿 tint 画的多是前景图标与文字（规范 §9.1 X-1）；开关自己显式用 base（ZToggle）。
    func zAccent(_ accent: ZTokens.Accent) -> some View {
        environment(\.zAccent, accent)
            .tint(accent.text)
    }
}

/// 解析为当前环境强调色的 ShapeStyle：`.fill(ZAccentStyle())`（开关、进度、光晕、描边等图形）。
/// 前景文字 / 图标用 `ZAccentTextStyle`，主按钮 / 选中胶囊用 `ZAccentFillStyle` + `ZAccentOnFillStyle`（规范 §9.1）。
public struct ZAccentStyle: ShapeStyle, Sendable {
    /// 0...1，强调色的不透明度（例如命中行底色用 0.09）。
    public var opacity: Double
    public init(opacity: Double = 1) { self.opacity = opacity }
    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.zAccent.color.opacity(opacity)
    }
}

/// 强调色前景（accent.*.text）：小字、链接、索引条、搜索高亮、「+」等图标。浅色加深，过 WCAG 正文 4.5（规范 §9.1，X-1）。
public struct ZAccentTextStyle: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { environment.zAccent.text }
}

/// 强调色底（accent.*.fill）：主按钮、选中胶囊，与 `ZAccentOnFillStyle` 配对（规范 §9.1，X-2）。
public struct ZAccentFillStyle: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { environment.zAccent.fill }
}

/// accent.*.fill 上的文字（green / orange 为黑字）。
public struct ZAccentOnFillStyle: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { environment.zAccent.onFill }
}

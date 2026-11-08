// 组合语义填充：把原型手机色板 screen.*（--s1…--s4、--t4、--bg）映射成组件可用的 ShapeStyle。

import SwiftUI
import UIKit

/// 卡片表面（原型 --s1）。在 sheet 内（底色本身是 --s1）自动抬到列表色 --s2，保持“列表比 sheet 亮”的层级。
public struct ZCardFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.zInSheet ? ZTokens.Colors.screenS2 : ZTokens.Colors.screenS1
    }
}

/// 列表表面（原型 --s2：sheet 内列表、指令建议、资料库统计）。
public struct ZListFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { ZTokens.Colors.screenS2 }
}

/// 轨道/输入底色（原型 --s3：分段控件底、搜索框、按钮 ghost 底）。
public struct ZTrackFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { ZTokens.Colors.screenS3 }
}

/// 滑块/选中块（原型 --s4：分段控件的 knob、吐司底）。
public struct ZKnobFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { ZTokens.Colors.screenS4 }
}

/// 第四级文字（原型 --t4：箭头、序号、未测延迟）。
public struct ZQuaternaryText: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color { ZTokens.Colors.screenT4 }
}

/// 开关颜色（原型 --green / --s4）。
public enum ZSwitchColor {
    public static var on: Color { ZTokens.Colors.screenGreen }
    /// 开关“关”轨道（原型 --s4）。
    public static var off: Color { ZTokens.Colors.screenS4 }
}

private struct ZInSheetKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// 当前内容是否处在 Zephyr sheet 中（底色 --s1），卡片据此抬到 --s2。
    var zInSheet: Bool {
        get { self[ZInSheetKey.self] }
        set { self[ZInSheetKey.self] = newValue }
    }
}

private struct ZStaticRenderingKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// 静态渲染（快照测试）：关闭数字滚动、曲线缓入与逐帧时间线，使截图确定、不受真实时钟影响。生产代码不设置。
    var zStaticRendering: Bool {
        get { self[ZStaticRenderingKey.self] }
        set { self[ZStaticRenderingKey.self] = newValue }
    }
}

/// 页面底色（原型 --bg：深色纯黑、浅色 #F2F2F7）。
public enum ZPage {
    public static var background: Color { ZTokens.Colors.screenBg }
}

public extension View {
    /// 铺满的页面底色（深色纯黑 / 浅色 #F2F2F7）。
    func zPageBackground() -> some View {
        background(ZPage.background.ignoresSafeArea())
    }
}

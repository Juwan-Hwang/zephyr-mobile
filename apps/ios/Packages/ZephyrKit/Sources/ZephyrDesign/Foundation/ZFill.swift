// 组合语义填充。原型的表面层级（--s1…--s4、--t4、页面底色）在 ZTokens 里没有一一对应的 token，
// 这里用 iOS 17 自定义 ShapeStyle 在“组件库这一层”把 token 组合成原型的观感，组件里不写深浅三元。
// 已在 NOTES-D.md 请求 A 补：surfaceCard / fillTrack / fillKnob / textQuaternary / bgPage。

import SwiftUI
import UIKit

/// 卡片表面：深色 = surfaceRaised（深色玻璃，靠 1px borderSubtle 分层）；浅色 = surfaceElevated（原型浅色卡片为纯白）。
public struct ZCardFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? ZTokens.Colors.surfaceRaised : ZTokens.Colors.surfaceElevated
    }
}

/// 轨道/输入底色（原型 --s3：分段控件底、搜索框、按钮 ghost 底）。
public struct ZTrackFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color {
        ZTokens.Colors.borderDefault
    }
}

/// 滑块/选中块（原型 --s4：分段控件的 knob、吐司底）。深色叠一层 borderDefault，浅色用白色抬起。
public struct ZKnobFill: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? ZTokens.Colors.borderPrimary : ZTokens.Colors.surfaceElevated
    }
}

/// 第四级文字（原型 --t4 20%：箭头、序号、未测延迟）。
public struct ZQuaternaryText: ShapeStyle, Sendable {
    public init() {}
    public func resolve(in environment: EnvironmentValues) -> Color {
        ZTokens.Colors.borderStrong
    }
}

/// 开关“开”的颜色（原型 --green #30D158 / 浅色 #34C759，等于 latencyGood）。
public enum ZSwitchColor {
    public static var on: Color { ZTokens.Colors.latencyGood }
    /// 开关“关”轨道（原型 --s4）。
    public static var off: Color { ZTokens.Colors.borderStrong }
}

/// 页面底色：深色纯黑、浅色 #F2F2F7（等于系统 grouped background）。
public enum ZPage {
    public static var background: Color { Color(uiColor: .systemGroupedBackground) }
}

public extension View {
    /// 铺满的页面底色（深色纯黑 / 浅色 #F2F2F7）。
    func zPageBackground() -> some View {
        background(ZPage.background.ignoresSafeArea())
    }
}

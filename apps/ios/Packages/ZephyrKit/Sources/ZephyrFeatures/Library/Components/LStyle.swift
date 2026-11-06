// LStyle — L 负责的资料库类页面共用的视觉常量与修饰符（只引用 ZTokens）。
//
// 原型（pages.css）里的分组卡片 .grp / 行 .gr / 分区标题 .sec / 页脚 .ft 在这里统一成修饰符。
// D 的 Z* 组件落地后，可把这里的实现替换为 ZCard / ZSettingsRow / ZSectionHeader（接口不变）。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

enum LStyle {
    /// 页面背景：原型 --bg 深 #000 / 浅 #F2F2F7，正是系统分组背景。tokens 暂无 bgPage（已在 NOTES-L 请 A 增补）。
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    /// 页面左右边距（原型 .grp margin 16）
    static let margin = ZTokens.Layout.pageMargin
    /// 卡片圆角（原型 .grp 18px，取最接近的 token）
    static let cardRadius = ZTokens.Radius.md
    /// 页面标题左缩进（原型 .pgh padding 22 = 16 + 6）
    static let titleInset = ZTokens.Layout.pageMargin + ZTokens.Space.n2
    /// 行最小高度（原型 .gr min-height 56）
    static let rowMinHeight = ZTokens.Layout.touchMinIos + ZTokens.Space.n4

    /// 卡片底色：深色用 surfaceRaised（原型 s1 #0c0c0e），浅色用 bgElevated（白）。
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? ZTokens.Colors.surfaceRaised : ZTokens.Colors.bgElevated
    }
}

/// 分组卡片外观：底色 + 1px 细边 + 连续圆角。
struct LCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = LStyle.cardRadius

    func body(content: Content) -> some View {
        content
            .background(LStyle.cardFill(scheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(ZTokens.Colors.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func lCard(radius: CGFloat = LStyle.cardRadius) -> some View { modifier(LCardBackground(radius: radius)) }

    /// 页脚说明文字（原型 .ft）。
    func lFootnoteStyle() -> some View {
        self.zType(.footnote)
            .foregroundStyle(ZTokens.Colors.textTertiary)
            .padding(.horizontal, LStyle.titleInset)
            .padding(.top, ZTokens.Space.n3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 从引擎设置流读取强调色并作为 tint 下发（H 的根视图若已设 tint，这里与之一致）。
    func lAccent(from engine: any ZephyrEngine) -> some View { modifier(LAccentModifier(engine: engine)) }
}

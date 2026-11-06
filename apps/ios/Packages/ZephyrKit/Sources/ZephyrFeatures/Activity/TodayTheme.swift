// 今日卡片的三套主题（原型 14：`.card[data-pal]` + windArt 的 PAL）。
//   夜 #02040a：蓝 → 天蓝 → 白 的流线，白字
//   晨 #F6EEE6：橙 → 杏 → 米 的流线，墨字
//   雾 #ECEDEF：石墨灰流线，墨字
// 这些是"生成艺术"的固定色板（导出成图片后不随深浅色变化），ZTokens 没有对应 token，
// 集中在此并注明出处；已在 NOTES-H.md 请 A 评估是否收进 tokens（art.today.*）。

import SwiftUI

enum TodayTheme: String, CaseIterable, Identifiable, Sendable {
    case night, dawn, mist

    var id: String { rawValue }

    var title: String {
        switch self { case .night: "夜"; case .dawn: "晨"; case .mist: "雾" }
    }

    /// 卡片底色（原型 `.card` background）。
    var background: Color {
        switch self {
        case .night: Self.rgb(0x02, 0x04, 0x0A)
        case .dawn: Self.rgb(0xF6, 0xEE, 0xE6)
        case .mist: Self.rgb(0xEC, 0xED, 0xEF)
        }
    }

    /// windArt 的三个色标（原型 PAL）：渐变 0 → .3 → .65 → 1 依次用 [0]@0、[0]@.7、[1]@.85、[2]@.6。
    var strokes: (Color, Color, Color) {
        switch self {
        case .night: (Self.rgb(10, 132, 255), Self.rgb(100, 210, 255), Self.rgb(255, 255, 255))
        case .dawn: (Self.rgb(255, 122, 69), Self.rgb(255, 176, 120), Self.rgb(255, 226, 190))
        case .mist: (Self.rgb(60, 64, 72), Self.rgb(120, 126, 138), Self.rgb(30, 32, 36))
        }
    }

    var isDark: Bool { self == .night }

    /// 主文字（原型：夜 #fff；晨/雾 #16181c）。
    var primary: Color { isDark ? .white : Self.ink }
    /// 日期、单位（原型：夜 .6 白；晨/雾 .5 墨）。
    var secondary: Color { isDark ? .white.opacity(0.6) : Self.ink.opacity(0.5) }
    /// 统计说明、"今日"（原型：夜 .5/.45 白；晨/雾 .5 墨）。
    var tertiary: Color { isDark ? .white.opacity(0.5) : Self.ink.opacity(0.5) }
    /// 底部分隔线（原型 `.cft` border-top .5px）。
    var rule: Color { isDark ? .white.opacity(0.12) : .black.opacity(0.1) }
    /// 文字区下方的渐变遮罩（原型 `.cin2`：transparent → 底色 .92/.94 @38%）。
    var scrim: Color { background.opacity(isDark ? 0.92 : 0.94) }

    private static let ink = rgb(0x16, 0x18, 0x1C)

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

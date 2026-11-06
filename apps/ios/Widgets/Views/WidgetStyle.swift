// 小组件 / 实时活动共用的样式解析：强调色、深链。颜色、字号、间距一律取自 ZTokens。

import SwiftUI
import ZephyrDesign

enum WidgetStyle {
    /// SharedState.accent（blue|green|orange|pink）→ 强调色。
    static func accent(_ raw: String) -> Color {
        (ZTokens.Accent(rawValue: raw) ?? .blue).color
    }

    /// 小组件里大数字的 Dynamic Type 上限：再大会被系统裁切，改由 minimumScaleFactor 收缩。
    static let maxDynamicType: DynamicTypeSize = .accessibility1
}

/// 小组件 / 实时活动的点击目标（H 的 ZephyrFeatures.DeepLink 能解析的 zephyr:// 链接）。
enum WidgetLinks {
    static let home = URL(string: "zephyr://home")!
    static let today = URL(string: "zephyr://today")!
    static let library = URL(string: "zephyr://library")!

    static func scene(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "zephyr://scene/\(safe)") ?? home
    }
}

// SharedState 的状态/模式标题在 Shared/Core 里是中文 String（PacketTunnel 也用它，不依赖 UI 包）。
// 小组件显示时用标题本身作 key 到本扩展的 String Catalog（Widgets/Localizable.xcstrings）查一次，
// 英文等语言即可生效；查不到时回落中文原文（快照测试的 Bundle.main 没有 catalog，结果不变）。

import Foundation

extension SharedState.Status {
    /// 本地化后的状态名（“已连接” / “Connected”）。
    var displayTitle: String { String(localized: String.LocalizationValue(title)) }
}

extension SharedState.Mode {
    /// 本地化后的模式名（“规则” / “Rule”）。
    var displayTitle: String { String(localized: String.LocalizationValue(title)) }
}

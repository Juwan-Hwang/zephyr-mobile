// 本地化入口（返回 String 的文案）。键就是中文原文（与 Localizable.xcstrings 的键一致）。
// `ZL.bundle` 默认为 nil = 不翻译，原样返回中文：单测（含 Linux）因此稳定，不受设备语言影响。
// App 与 Widgets 启动时设置 `ZL.bundle = .main`，之后按系统语言取 Localizable.xcstrings 的译文。

import Foundation

public enum ZL {
    /// nil = 不查表（测试）；App / Widgets 在启动时设为 `.main`。
    nonisolated(unsafe) public static var bundle: Bundle?

    /// 计数单位用“万 / 亿”还是 K / M / B：未设 bundle（测试）或界面语言为中文时用中文单位。
    /// 按 bundle 实际选中的本地化判断（不是系统语言），与查表结果始终一致。
    public static var usesChineseUnits: Bool {
        guard let lang = bundle?.preferredLocalizations.first else { return true }
        return lang.hasPrefix("zh")
    }

    /// 界面实际使用的语言（bundle 选中的本地化）；单测（bundle 为 nil）为 nil。
    public static var uiLocale: Locale? {
        bundle?.preferredLocalizations.first.map { Locale(identifier: $0) }
    }

    /// 紧凑计数的单位体系：中文“万 / 亿”、日文“万 / 億”、韩文“만 / 억”、英文 K / M / B，
    /// 其余语言用系统的本地化紧凑写法（俄文“13,1 млн”等，D-P2-12）。
    public enum CountUnits: Sendable, Equatable { case zh, ja, ko, western, localized(String) }

    public static var countUnits: CountUnits { units(forLocalization: bundle?.preferredLocalizations.first) }

    /// nil（测试、未设 bundle）按中文。
    public static func units(forLocalization lang: String?) -> CountUnits {
        guard let lang else { return .zh }
        if lang.hasPrefix("zh") { return .zh }
        if lang.hasPrefix("ja") { return .ja }
        if lang.hasPrefix("ko") { return .ko }
        if lang.hasPrefix("en") { return .western }
        return .localized(lang)
    }

    /// 直接查表。缺译文时回落到键本身（中文原文）。
    public static func tr(_ key: String) -> String {
        guard let bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// 同一中文在不同位置需要不同译文时（如“规则”：模式名用单数 Rule，页面标题用复数 Rules），
    /// 查表键为 `key#context`，表里的 zh-Hans 译文写回原文；缺表或缺译文时回落到 `key`。
    public static func tr(_ key: String, context: String) -> String {
        guard let bundle else { return key }
        let composite = key + "#" + context
        let v = bundle.localizedString(forKey: composite, value: key, table: nil)
        return v == composite ? key : v
    }

    /// 带参数的文案：键是含 `%lld` / `%@` / `%1$@` 的格式串；译文可用位置参数调整语序，
    /// xcstrings 里的复数变体由 stringsdict 按 `locale` 的复数规则选择。
    public static func f(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: bundle == nil ? nil : Locale.current, arguments: args)
    }

    /// 只含字符串参数的文案（`%@` 或 `%1$@` 位置参数）。不经 String(format:)，Linux 也能用。
    public static func s(_ key: String, _ args: String...) -> String {
        var out = tr(key)
        for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "%\(i + 1)$@", with: a) }
        for a in args {
            guard let r = out.range(of: "%@") else { break }
            out.replaceSubrange(r, with: a)
        }
        return out
    }
}

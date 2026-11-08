// 本地化入口（返回 String 的文案）。键就是中文原文（与 Localizable.xcstrings 的键一致）。
// `ZL.bundle` 默认为 nil = 不翻译，原样返回中文：单测（含 Linux）因此稳定，不受设备语言影响。
// App 与 Widgets 启动时设置 `ZL.bundle = .main`，之后按系统语言取 Localizable.xcstrings 的译文。

import Foundation

public enum ZL {
    /// nil = 不查表（测试）；App / Widgets 在启动时设为 `.main`。
    public static var bundle: Bundle?

    /// 直接查表。缺译文时回落到键本身（中文原文）。
    public static func tr(_ key: String) -> String {
        guard let bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
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

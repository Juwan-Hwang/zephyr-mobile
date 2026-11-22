// 指令栏本地行（切模式 / 连接-断开 / 打开场景或页面）的触发规则，Core 与 Mock 共用。
// #1 A 2026-11-22 20:43 决定（契约 §16.d E41 + 规范 §9.5 回车执行首行），三端以 Android 现规则统一：
//   输入去首尾空白、不分大小写，对标题和别名匹配。
//   - 执行类行（切模式、连接 / 断开）：整词相等，或前缀匹配且输入 ≥ 2 个字符（单个字符不能把执行类动作顶成首行）。
//   - 导航类行（打开场景 / 页面）：子串匹配（只是打开页面，可撤回）。

import Foundation

public enum CommandMatch {
    /// 规范化：去首尾空白 + 小写。
    public static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 执行类：任一名称与输入整词相等，或以输入开头且输入 ≥ 2 个字符。`q` 须已 normalize。
    public static func action(_ q: String, names: [String]) -> Bool {
        guard !q.isEmpty else { return false }
        return names.contains { n in
            let n = normalize(n)
            return n == q || (q.count >= 2 && n.hasPrefix(q))
        }
    }

    /// 导航类：任一名称包含输入。`q` 须已 normalize。
    public static func navigation(_ q: String, names: [String]) -> Bool {
        guard !q.isEmpty else { return false }
        return names.contains { normalize($0).contains(q) }
    }

    /// 连接 / 断开的别名（两端一致：含「开」「关」整词）。
    public static let toggleAliases = ["连接", "断开", "connect", "disconnect", "开", "关"]
}

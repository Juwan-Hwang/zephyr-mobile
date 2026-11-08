// ImportRequest —— 外部链接（clash:// / mihomo://install-config?url=…）解析出的一次导入请求（纯值，便于单测）。
// 外部链接不得静默导入（REVIEW-Q2 X-P1-1）：UI 先展示来源域名（http 另加警告），用户确认后才导入。

import Foundation

struct ImportRequest: Identifiable, Equatable, Sendable {
    let payload: String
    var id: String { payload }

    var host: String { URL(string: payload)?.host ?? payload }
    var isInsecure: Bool { URL(string: payload)?.scheme?.lowercased() == "http" }

    /// 确认弹窗正文：来源、（http 时的）明文警告、信任提示。
    var message: String {
        var text = String(localized: "来源：\(host)")
        if isInsecure { text += "\n" + String(localized: "此链接未加密（http），内容可能被窃听或篡改。") }
        text += "\n" + String(localized: "请确认这个链接来自你信任的服务商。")
        return text
    }

    /// 解析导入链接；非 clash/mihomo、不是 install-config 或缺少 http(s) 的 url 参数返回 nil。
    static func subscriptionURL(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "clash" || scheme == "mihomo",
              url.host?.lowercased() == "install-config",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: raw), let s = target.scheme?.lowercased(), s == "https" || s == "http",
              target.host?.isEmpty == false
        else { return nil }
        return raw
    }
}

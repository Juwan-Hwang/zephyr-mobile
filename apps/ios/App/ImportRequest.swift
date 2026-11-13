// ImportRequest —— 外部链接（clash:// / clashmeta:// / mihomo://install-config?url=…，以及桌面“同步到手机”的
// zephyr://import…，契约 §15）解析出的一次导入请求（纯值，便于单测）。
// 外部链接不得静默导入（REVIEW-Q2 X-P1-1）：UI 先展示来源域名（http 另加警告），用户确认后才导入。

import Foundation

struct ImportRequest: Identifiable, Equatable, Sendable {
    /// `.url` 导入时是订阅地址；桌面同步码时是整条 zephyr://import 链接（交给引擎按 §15 解析，可能多条）。
    let payload: String
    /// payload 是 zephyr://import 桌面同步码（引擎按二维码来源导入）。
    var isDesktopSync = false
    var id: String { payload }

    /// 用来展示来源的订阅地址：单条同步码取其 url 参数；多条（d=）时为 nil。
    private var target: URL? {
        guard isDesktopSync else { return URL(string: payload) }
        return Self.queryValue("url", in: payload).flatMap(URL.init(string:))
    }

    var host: String { target?.host ?? (isDesktopSync ? String(localized: "Zephyr 桌面") : payload) }
    var isInsecure: Bool { target?.scheme?.lowercased() == "http" }

    /// 确认弹窗正文：来源、（http 时的）明文警告、信任提示。
    var message: String {
        var text = String(localized: "来源：\(host)")
        if isInsecure { text += "\n" + String(localized: "此链接未加密（http），内容可能被窃听或篡改。") }
        text += "\n" + String(localized: "请确认这个链接来自你信任的服务商。")
        return text
    }

    /// 外部链接 → 导入请求；不认识返回 nil。
    static func from(url: URL) -> ImportRequest? {
        if let sub = subscriptionURL(from: url) { return ImportRequest(payload: sub) }
        if isDesktopSync(url) { return ImportRequest(payload: url.absoluteString, isDesktopSync: true) }
        return nil
    }

    /// zephyr://import?url=…｜zephyr://import?v=1&d=…（契约 §15）。只认形态，内容由引擎校验。
    static func isDesktopSync(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "zephyr", url.host?.lowercased() == "import" else { return false }
        return queryValue("url", in: url.absoluteString) != nil || queryValue("d", in: url.absoluteString) != nil
    }

    private static func queryValue(_ name: String, in s: String) -> String? {
        URLComponents(string: s)?.queryItems?.first(where: { $0.name == name })?.value
    }

    /// 解析导入链接；非 clash/clashmeta/mihomo、不是 install-config 或缺少 http(s) 的 url 参数返回 nil。
    static func subscriptionURL(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["clash", "clashmeta", "mihomo"].contains(scheme),
              url.host?.lowercased() == "install-config",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: raw), let s = target.scheme?.lowercased(), s == "https" || s == "http",
              target.host?.isEmpty == false
        else { return nil }
        return raw
    }
}

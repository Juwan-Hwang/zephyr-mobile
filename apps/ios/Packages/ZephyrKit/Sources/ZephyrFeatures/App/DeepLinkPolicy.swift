// 深链来源与确认策略（REVIEW H-P2-21）。纯 Swift，便于单测（Tests/ZephyrFeaturesTests/DeepLinkPolicyTests.swift）。
//
// 问题：任何 App / 网页都能打开 zephyr://disconnect、zephyr://mode/global，无提示地断开 VPN 或切模式。
//
// 区分方式：
//   - App 内（指令层、按钮、App Intents / 快捷指令 / 控制中心）不走 URL，直接调用 `AppModel.open(_:source: .trusted)`
//     或 AppModel 的动作方法，天然可信。
//   - URL 一律先当作"外部"。我们自己的小组件 / 实时活动要执行会改变状态的链接时，在 URL 上附带
//     `zt=<令牌>`（`DeepLink.url(trustToken:)`）。令牌由 App 首次启动时随机生成（≥ 16 字符），存进 App Group，
//     App 进程启动时注入 `AppModel.trustedLinkToken`，小组件进程从 App Group 读出来拼链接。
//     其他 App 读不到 App Group，伪造不了令牌。比较用定长时间比较。
//   - 只读 / 导航类链接（home、scene、today、command…）不论来源都直接执行。
//   - 会改变状态的链接（connect / disconnect / toggle / mode/*）来自外部时，只有真的会改变状态才弹确认；
//     例如已连接时的 zephyr://connect 是空操作，直接忽略确认。

import Foundation
import ZephyrKit

/// 深链来源。
public enum DeepLinkSource: Sendable, Hashable {
    /// 其他 App / 网页 / 未带有效令牌的 URL。
    case external
    /// App 内调用，或带有效令牌的小组件 / 实时活动链接。
    case trusted
}

public extension DeepLink {
    /// 会改变连接状态或代理模式的动作。
    var changesState: Bool {
        switch self {
        case .connect, .disconnect, .toggle, .mode: true
        case .home, .sheet, .command, .push: false
        }
    }

    /// 小组件令牌所在的 query 名。
    static let trustQueryName = "zt"

    /// 附带可信令牌的 URL（小组件 / 实时活动用）。令牌为空时等同 `url`。
    func url(trustToken: String) -> URL {
        guard !trustToken.isEmpty, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let value = trustToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? trustToken
        c.percentEncodedQueryItems = (c.percentEncodedQueryItems ?? []) + [URLQueryItem(name: Self.trustQueryName, value: value)]
        return c.url ?? url
    }
}

/// 外部深链的确认文案。
public struct DeepLinkPrompt: Equatable, Sendable {
    public var title: String
    public var message: String
    public var confirm: String
    public var destructive: Bool
}

/// 等待用户确认的外部深链。
public struct PendingDeepLink: Equatable, Sendable {
    public var link: DeepLink
    public var prompt: DeepLinkPrompt
}

enum DeepLinkPolicy {
    /// 令牌最短长度：过短的令牌（含空串）一律不认。
    static let minTokenLength = 16

    /// URL 的来源：带有与 `trustedToken` 一致的 `zt` 令牌 → trusted，否则 external。
    static func source(of url: URL, trustedToken: String?) -> DeepLinkSource {
        guard let expected = trustedToken, expected.count >= minTokenLength,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let given = items.last(where: { $0.name == DeepLink.trustQueryName })?.value
        else { return .external }
        return constantTimeEquals(given, expected) ? .trusted : .external
    }

    /// 是否需要先让用户确认。
    static func requiresConfirmation(_ link: DeepLink, source: DeepLinkSource, isOn: Bool, mode: ProxyMode) -> Bool {
        guard source == .external, link.changesState else { return false }
        switch link {
        case .connect: return !isOn
        case .disconnect: return isOn
        case .toggle: return true
        case .mode(let raw): return ProxyMode(rawValue: raw).map { $0 != mode } ?? false
        default: return false
        }
    }

    /// 确认弹窗文案；非状态类链接返回 nil。
    static func prompt(for link: DeepLink, isOn: Bool) -> DeepLinkPrompt? {
        switch link {
        case .connect:
            return DeepLinkPrompt(title: ZL.tr("连接 Zephyr？"), message: ZL.tr("另一个 App 请求开启 Zephyr。"), confirm: ZL.tr("连接"), destructive: false)
        case .disconnect:
            return DeepLinkPrompt(title: ZL.tr("断开 Zephyr？"), message: ZL.tr("另一个 App 请求断开 Zephyr，断开后流量不再经过代理。"),
                                  confirm: ZL.tr("断开"), destructive: true)
        case .toggle:
            return prompt(for: isOn ? .disconnect : .connect, isOn: isOn)
        case .mode(let raw):
            guard let m = ProxyMode(rawValue: raw) else { return nil }
            let name = modeName(m)
            return DeepLinkPrompt(title: ZL.s("切换到%@模式？", name), message: ZL.s("另一个 App 请求把代理模式改为“%@”。", name),
                                  confirm: ZL.tr("切换"), destructive: m == .direct)
        case .home, .sheet, .command, .push:
            return nil
        }
    }

    static func modeName(_ m: ProxyMode) -> String {
        switch m { case .rule: ZL.tr("规则"); case .global: ZL.tr("全局"); case .direct: ZL.tr("直连") }
    }

    /// 定长时间比较（长度不同直接 false；长度本身不是秘密）。
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

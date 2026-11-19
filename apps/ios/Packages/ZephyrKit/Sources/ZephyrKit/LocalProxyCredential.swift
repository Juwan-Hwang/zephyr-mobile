// LocalProxyCredential —— 本地代理凭据的格式（契约 §16.g ①，U9）：纯值、Linux 可编译。
// "zephyr:<24 位>"：用户名固定 zephyr，密码取自去掉易混 0 O 1 l I 的字母表；两端同一格式。
// 生成与存储由平台引擎做（CoreEngine 存钥匙串、MockEngine 内存），这里只管格式与复制用的 URL。

import Foundation

public enum LocalProxyCredential {
    public static let username = "zephyr"
    public static let passwordLength = 24
    public static let alphabet: [Character] = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    /// 本地代理只监听回环地址（§14.z ④ bind-address: 127.0.0.1）。
    public static let host = "127.0.0.1"

    /// 用给定随机源生成完整凭据（生产用 `SystemRandomNumberGenerator`）。
    public static func generate<G: RandomNumberGenerator>(using rng: inout G) -> String {
        let pass = String((0..<passwordLength).map { _ in alphabet.randomElement(using: &rng)! })
        return "\(username):\(pass)"
    }

    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    /// 是否为本机生成的合法凭据：`zephyr:` + 24 位字母表字符。不合法的存量值由平台重新生成。
    public static func isWellFormed(_ credential: String) -> Bool {
        let prefix = username + ":"
        guard credential.hasPrefix(prefix) else { return false }
        let pass = credential.dropFirst(prefix.count)
        return pass.count == passwordLength && pass.allSatisfy { alphabet.contains($0) }
    }

    /// 冒号后的密码部分（无冒号时原样返回）。
    public static func password(of credential: String) -> String {
        guard let i = credential.firstIndex(of: ":") else { return credential }
        return String(credential[credential.index(after: i)...])
    }

    /// 冒号前的用户名部分（无冒号时为固定用户名）。
    public static func user(of credential: String) -> String {
        guard let i = credential.firstIndex(of: ":") else { return username }
        return String(credential[..<i])
    }

    public enum Scheme: String, Sendable, CaseIterable {
        case http
        case socks5
    }

    /// 复制给其他 App 的地址：`http://zephyr:<密码>@127.0.0.1:<端口>`；SOCKS5 同格式。
    /// 字母表只含字母数字，用户名密码无需百分号编码。
    public static func url(_ scheme: Scheme, credential: String, port: Int32) -> String {
        "\(scheme.rawValue)://\(user(of: credential)):\(password(of: credential))@\(host):\(port)"
    }
}

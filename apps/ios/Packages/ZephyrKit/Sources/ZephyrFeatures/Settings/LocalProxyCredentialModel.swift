// LocalProxyCredentialModel —— 本地代理页的凭据部分（契约 §16.g ①，U9）。
// 读 `engine.localProxyCredential()`（与写进隧道配置的是同一个），密码默认遮挡、点按显示；
// 复制 HTTP / SOCKS5 地址时按敏感内容写剪贴板（仅本机、60 s 过期）；重新生成交给引擎（运行中热重载）。

import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers
import ZephyrKit

@MainActor
@Observable
final class LocalProxyCredentialModel {
    @ObservationIgnored let engine: any ZephyrEngine
    @ObservationIgnored private let pasteboard: @MainActor (String) -> Void

    /// nil = 还没读到。
    private(set) var credential: String?
    /// 密码是否明文显示（默认遮挡；重新生成后回到遮挡）。
    var isRevealed = false
    private(set) var isResetting = false

    /// 敏感内容在剪贴板里的寿命（契约 §16.g ①）。
    nonisolated static let clipboardLifetime: TimeInterval = 60
    nonisolated static let mask: Character = "•"

    init(engine: any ZephyrEngine, pasteboard: (@MainActor (String) -> Void)? = nil) {
        self.engine = engine
        self.pasteboard = pasteboard ?? { LocalProxyCredentialModel.copySensitive($0) }
    }

    var username: String { credential.map(LocalProxyCredential.user(of:)) ?? LocalProxyCredential.username }

    var password: String? { credential.map(LocalProxyCredential.password(of:)) }

    /// 行上显示的密码：未读到为“—”，遮挡时与密码等长的圆点。
    var displayedPassword: String {
        guard let p = password else { return "—" }
        return isRevealed ? p : String(repeating: Self.mask, count: p.count)
    }

    func load() async {
        credential = await engine.localProxyCredential()
    }

    /// 复制用的完整地址；凭据未读到为 nil。
    func url(_ scheme: LocalProxyCredential.Scheme, port: Int32) -> String? {
        credential.map { LocalProxyCredential.url(scheme, credential: $0, port: port) }
    }

    /// 行副标题：遮挡时密码换成圆点，避免旁人看到。
    func displayedURL(_ scheme: LocalProxyCredential.Scheme, port: Int32) -> String? {
        guard credential != nil else { return nil }
        let masked = "\(username):\(displayedPassword)"
        return "\(scheme.rawValue)://\(masked)@\(LocalProxyCredential.host):\(port)"
    }

    /// 写剪贴板；返回是否已复制（凭据未读到时不复制）。
    @discardableResult
    func copy(_ scheme: LocalProxyCredential.Scheme, port: Int32) -> Bool {
        guard let u = url(scheme, port: port) else { return false }
        pasteboard(u)
        return true
    }

    func reset() async {
        guard !isResetting else { return }
        isResetting = true
        defer { isResetting = false }
        credential = await engine.resetLocalProxyCredential()
        isRevealed = false
    }

    /// 仅本机（不进通用剪贴板 / Handoff）、60 s 后系统自动清除。
    static func copySensitive(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(clipboardLifetime)])
    }
}

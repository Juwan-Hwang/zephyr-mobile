// SubscriptionImporter — 导入订阅（粘贴链接 / 扫码 / 从电脑导入 / 文件）的共享模型。订阅页与引导页共用。

import Foundation
import Observation
import ZephyrKit

/// 四种导入方式（原型 ob1 与订阅页“+”）。
enum SubscriptionImportMethod: String, CaseIterable, Identifiable, Sendable {
    case paste, scan, desktop, file
    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: ZL.tr("粘贴链接")
        case .scan: ZL.tr("扫描二维码")
        case .desktop: ZL.tr("从电脑上的 Zephyr 导入")
        case .file: ZL.tr("从文件导入")
        }
    }

    var systemImage: String {
        switch self {
        case .paste: "doc.on.clipboard"
        case .scan: "qrcode.viewfinder"
        case .desktop: "desktopcomputer"
        case .file: "doc"
        }
    }
}

@MainActor
@Observable
final class SubscriptionImporter {
    enum Phase: Equatable {
        case idle
        case importing
        case done(Subscription)
        case failed(String)
    }

    @ObservationIgnored let engine: any ZephyrEngine
    private(set) var phase: Phase = .idle

    init(engine: any ZephyrEngine) { self.engine = engine }

    var isImporting: Bool { phase == .importing }
    var errorMessage: String? { if case .failed(let m) = phase { m } else { nil } }

    func reset() { phase = .idle }

    @discardableResult
    func importLink(_ text: String, fromClipboard: Bool = false) async -> Subscription? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { phase = .failed(ZL.tr("请粘贴订阅链接")); return nil }
        return await run(fromClipboard ? .clipboard : .url, s)
    }

    /// 二维码：普通订阅链接，或电脑上 Zephyr“同步到手机”显示的配对码（同样走 qr 来源，由引擎解析）。
    @discardableResult
    func importQR(_ payload: String) async -> Subscription? {
        await run(.qr, payload)
    }

    /// 文件：读取内容后以 file 来源导入（契约：payload = 文件内容）。
    @discardableResult
    func importFile(at url: URL) async -> Subscription? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // 读文件放到后台线程（大文件不卡主线程）；安全作用域在 await 期间保持打开。
        let text = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
        guard let text else {
            phase = .failed(ZL.tr("无法读取这个文件"))
            return nil
        }
        return await run(.file, text)
    }

    private func run(_ source: ImportSource, _ payload: String) async -> Subscription? {
        phase = .importing
        do {
            let sub = try await engine.importSubscription(source: source, payload: payload)
            phase = .done(sub)
            return sub
        } catch let e as ZephyrError {
            phase = .failed(Self.message(for: e.code))
        } catch {
            phase = .failed(ZL.tr("导入失败"))
        }
        return nil
    }

    static func message(for code: ErrorCode) -> String {
        switch code {
        case .subscriptionInvalid: ZL.tr("无法识别的订阅链接或配置")
        case .subscriptionFetchFailed: ZL.tr("无法获取订阅，请检查网络后重试")
        case .networkUnavailable: ZL.tr("网络不可用")
        case .storageFull: ZL.tr("设备存储空间不足")
        case .cancelled: ZL.tr("已取消")
        default: ZL.tr("导入失败")
        }
    }
}

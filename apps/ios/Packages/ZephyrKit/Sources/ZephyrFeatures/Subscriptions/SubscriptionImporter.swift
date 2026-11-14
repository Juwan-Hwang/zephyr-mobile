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
    /// 每次导入递增；取消或新一次导入后，旧请求的结果被丢弃（引擎调用本身可能无法中途打断，REVIEW-Q2 P2）。
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var current: Task<Subscription, Error>?

    init(engine: any ZephyrEngine) { self.engine = engine }

    var isImporting: Bool { phase == .importing }
    var errorMessage: String? { if case .failed(let m) = phase { m } else { nil } }

    func reset() { phase = .idle }

    /// 取消进行中的导入：回到 idle，晚到的结果不会写入 phase，也不会返回给调用方。
    func cancel() {
        guard isImporting else { return }
        generation += 1
        current?.cancel()
        current = nil
        phase = .idle
    }

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
        generation += 1
        let mine = generation
        current?.cancel()
        phase = .importing
        let engine = engine
        let task = Task { () async throws -> Subscription in
            let existing = await Self.currentIds(engine)
            let sub = try await engine.importSubscription(source: source, payload: payload)
            // 取消时引擎调用可能已完成：新建的订阅撤回，已存在的（引擎去重返回旧条目）保持不动。
            if Task.isCancelled {
                if !existing.contains(sub.id) { try? await engine.deleteSubscription(id: sub.id) }
                throw CancellationError()
            }
            return sub
        }
        current = task
        let result = await task.result
        guard mine == generation else { return nil }
        current = nil
        switch result {
        case .success(let sub):
            phase = .done(sub)
            return sub
        case .failure(let e as ZephyrError):
            phase = .failed(Self.message(for: e.code))
        case .failure:
            phase = .failed(ZL.tr("导入失败"))
        }
        return nil
    }

    /// 导入前已有的订阅 id（订阅流首个值）。
    private nonisolated static func currentIds(_ engine: any ZephyrEngine) async -> Set<String> {
        for await list in engine.subscriptions() { return Set(list.map(\.id)) }
        return []
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

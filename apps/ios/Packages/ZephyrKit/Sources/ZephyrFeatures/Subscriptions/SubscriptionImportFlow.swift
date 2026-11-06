// SubscriptionImportFlow — 根据选中的导入方式弹出对应界面（粘贴 / 扫码 / 电脑 / 文件），完成后回调。
// 用法：`.subscriptionImportFlow(method: $method, importer: importer) { sub in … }`

import SwiftUI
import UniformTypeIdentifiers
import ZephyrKit

struct SubscriptionImportFlow: ViewModifier {
    @Binding var method: SubscriptionImportMethod?
    let importer: SubscriptionImporter
    var onImported: (Subscription) -> Void

    /// 允许的配置文件类型：YAML（Clash/mihomo）、纯文本、JSON 与任意数据（部分订阅导出为无扩展名文件）。
    static let fileTypes: [UTType] = [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
                                      .plainText, .json, .data].compactMap { $0 }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: binding(.paste)) {
                PasteLinkSheet(importer: importer, onImported: onImported)
            }
            .fullScreenCover(isPresented: scanBinding) {
                QRScanSheet(desktop: method == .desktop) { code in
                    Task { if let s = await importer.importQR(code) { onImported(s) } }
                }
            }
            .fileImporter(isPresented: binding(.file), allowedContentTypes: Self.fileTypes) { result in
                guard case .success(let url) = result else { return }
                Task { if let s = await importer.importFile(at: url) { onImported(s) } }
            }
    }

    private func binding(_ m: SubscriptionImportMethod) -> Binding<Bool> {
        Binding(get: { method == m }, set: { if !$0, method == m { method = nil } })
    }

    private var scanBinding: Binding<Bool> {
        Binding(get: { method == .scan || method == .desktop },
                set: { if !$0, method == .scan || method == .desktop { method = nil } })
    }
}

extension View {
    func subscriptionImportFlow(method: Binding<SubscriptionImportMethod?>, importer: SubscriptionImporter,
                                onImported: @escaping (Subscription) -> Void) -> some View {
        modifier(SubscriptionImportFlow(method: method, importer: importer, onImported: onImported))
    }
}

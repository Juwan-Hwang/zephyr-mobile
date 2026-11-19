// OpenSourceLicensesView —— 设置 › 关于 › 开源许可（GPL-3.0 / MPL-2.0 合规，Refs #209）。
//
// 数据：App 资源里的 THIRD_PARTY_NOTICES.md、THIRD_PARTY_LICENSES.txt、LICENSE（仓库根原文件，见 project.yml），
// 由 ZephyrKit.OSSNotices 解析；页面不写死任何依赖。
//   源码获取   安装包整体按 GPL-3.0 分发 → 本仓库对应版本的 tag（NOTICES 许可口径）；mihomo 上游地址；MPL-2.0 说明
//   本 App     自有源码 MIT（LICENSE）· GPL-3.0 全文
//   Rust / Go  名称、版本、许可；展开看许可全文（缺许可文件的依赖显示说明 + 标准全文）
// 读文件失败时“源码获取”仍然显示（源码地址不依赖资源文件）。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

@MainActor @Observable
final class OpenSourceLicensesModel {
    enum Phase: Equatable {
        case loading
        case loaded(OSSNotices)
        case failed
    }

    private(set) var phase: Phase = .loading
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    var notices: OSSNotices? {
        if case .loaded(let n) = phase { return n }
        return nil
    }

    func load() async {
        guard notices == nil else { return }
        let bundle = bundle
        // 全文约 670 KB：在后台读与解析，不卡主线程。
        let result = await Task.detached(priority: .userInitiated) { Self.read(from: bundle) }.value
        phase = result.map(Phase.loaded) ?? .failed
    }

    nonisolated static func read(from bundle: Bundle) -> OSSNotices? {
        guard let notices = text(bundle, "THIRD_PARTY_NOTICES", "md"),
              let licenses = text(bundle, "THIRD_PARTY_LICENSES", "txt") else { return nil }
        let parsed = OSSNotices.parse(notices: notices, licenses: licenses, appLicense: text(bundle, "LICENSE", nil) ?? "")
        return parsed.all.isEmpty ? nil : parsed
    }

    private nonisolated static func text(_ bundle: Bundle, _ name: String, _ ext: String?) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
struct OpenSourceLicensesView: View {
    @State private var model: OpenSourceLicensesModel
    @State private var query = ""
    @State private var expanded: Set<String> = []

    init(bundle: Bundle = .main) {
        _model = State(initialValue: OpenSourceLicensesModel(bundle: bundle))
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        List {
            if !isSearching { sourceSection(model.notices) }
            switch model.phase {
            case .loading:
                Section {
                    ProgressView().frame(maxWidth: .infinity).accessibilityLabel(Text("加载中"))
                }
            case .failed:
                Section {
                    Text("许可文件读取失败")
                        .zType(.body)
                        .foregroundStyle(ZColor.t3)
                }
            case .loaded(let n):
                if !isSearching { appSection(n) }
                componentSection("Rust 组件", OSSNotices.filter(n.rust, query: query), in: n)
                componentSection("Go 组件", OSSNotices.filter(n.go, query: query), in: n, toolchain: isSearching ? nil : n.goToolchain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, PageMetrics.margin, for: .scrollContent)
        .zPageBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("搜索组件或许可证"))
        .overlay {
            if isSearching, let n = model.notices, OSSNotices.filter(n.all, query: query).isEmpty {
                ZEmptyState("无结果", message: "没有匹配的组件")
            }
        }
        .navigationTitle(Text("开源许可"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    // MARK: 源码获取（GPL-3.0 §6：随二进制告知对应源码的获取方式）

    private func sourceSection(_ n: OSSNotices?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                Text("本 App 静态链接了 mihomo（GPL-3.0），安装包整体按 GPL-3.0 分发；本 App 自有源码另以 MIT 许可发布。")
                Text("每个发布版本的对应源码即下方仓库中该版本的 tag，其中锁定了全部依赖版本。")
            }
            .zType(.footnote)
            .foregroundStyle(ZTokens.Colors.screenT1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, ZTokens.Space.n1)
            linkRow("源码仓库", url: OSSNotices.sourceRepository)
            linkRow("版本 tag", url: OSSNotices.sourceTags)
            if let m = n?.mihomo {
                linkRow("mihomo 源码", url: m.url, detail: m.version)
            }
        } header: {
            Text("源码获取")
        } footer: {
            Text("MPL-2.0 组件（如 uniffi）的源码见 crates.io 对应版本，本项目未修改任何 MPL-2.0 文件。")
        }
    }

    private func linkRow(_ title: LocalizedStringKey, url: URL, detail: String? = nil) -> some View {
        Link(destination: url) {
            HStack(spacing: ZTokens.Space.n3) {
                VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                    Text(title)
                        .zType(.body)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                    Text(verbatim: Self.display(url) + (detail.map { " · \($0)" } ?? ""))
                        .zType(.caption)
                        .foregroundStyle(ZColor.t3)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(ZColor.t3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isLink)
        .contextMenu {
            Button { UIPasteboard.general.url = url } label: {
                Label { Text(verbatim: url.absoluteString) } icon: { Image(systemName: "doc.on.doc") }
            }
        }
    }

    /// “github.com/Juwan-Hwang/zephyr-mobile”：去掉 https://。
    static func display(_ url: URL) -> String {
        let s = url.absoluteString
        return s.hasPrefix("https://") ? String(s.dropFirst("https://".count)) : s
    }

    // MARK: 本 App

    private func appSection(_ n: OSSNotices) -> some View {
        Section {
            if !n.appLicense.isEmpty {
                licenseRow(id: "app:zephyr", title: Text(verbatim: "Zephyr"),
                           subtitle: "\(Self.appVersion) · MIT", texts: [n.appLicense])
            }
            if let gpl = n.gplText {
                licenseRow(id: "app:gpl", title: Text("GPL-3.0 全文"),
                           subtitle: "GNU General Public License v3.0", texts: [gpl])
            }
        } header: {
            Text("本 App")
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: 组件

    @ViewBuilder
    private func componentSection(_ title: LocalizedStringKey, _ list: [OSSComponent], in n: OSSNotices,
                                  toolchain: (version: String, license: String)? = nil) -> some View {
        if !list.isEmpty || toolchain != nil {
            Section {
                ForEach(list) { c in
                    licenseRow(id: c.id, title: Text(verbatim: c.name), subtitle: "\(c.version) · \(c.license)",
                               texts: expanded.contains(c.id) ? n.licenseTexts(for: c) : [],
                               note: n.isMissingLicenseFile(c) || n.licenseTexts(for: c).isEmpty)
                }
                if let toolchain {
                    titleBlock(Text("Go 标准库与运行时"), subtitle: "\(toolchain.version) · \(toolchain.license)")
                        .accessibilityElement(children: .combine)
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(verbatim: ZFormat.count(Int64(list.count))).monospacedDigit()
                }
            }
        }
    }

    /// 可展开的一行：标题 + “版本 · 许可”；展开后是许可原文（等宽、可选择复制）。
    private func licenseRow(id: String, title: Text, subtitle: String, texts: [String], note: Bool = false) -> some View {
        DisclosureGroup(isExpanded: binding(id)) {
            if expanded.contains(id) {
                VStack(alignment: .leading, spacing: ZTokens.Space.n4) {
                    if note {
                        Text("未随包附带许可文件，许可依据其清单或仓库。")
                            .zType(.caption)
                            .foregroundStyle(ZColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                        Text(verbatim: text)
                            .zMono(.small)
                            .foregroundStyle(ZTokens.Colors.screenT1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // 许可原文为英文等左到右文本：RTL 界面下也不镜像。
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .padding(.vertical, ZTokens.Space.n2)
            }
        } label: {
            titleBlock(title, subtitle: subtitle)
        }
    }

    private func titleBlock(_ title: Text, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
            title
                .zType(.body)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Text(verbatim: subtitle)
                .zType(.caption)
                .foregroundStyle(ZColor.t3)
        }
        .padding(.vertical, ZTokens.Space.n1)
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }
}

#if DEBUG
#Preview("开源许可") {
    NavigationStack { OpenSourceLicensesView() }
        .preferredColorScheme(.dark)
}
#endif

// SettingsView — 设置页（原型 25）。分组：连接 / 检测 / 存储 / 外观 / 隐私；页脚“数据仅保存在此设备上”与版本号。
// 每次改动都经 SettingsStore 全量写回 updateSettings(patch:)；失败回滚并以吐司提示。
// 强调色与深浅色写回后由 RootView 读取 AppModel.settings 统一应用到整个 App。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

@MainActor
public struct SettingsView: View {
    @State private var store: SettingsStore
    @State private var storage: StorageInfo?
    @State private var toast: ZToastItem?

    public init(engine: any ZephyrEngine) {
        _store = State(initialValue: SettingsStore(engine: engine))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "设置", showsNumber: false)
                VStack(alignment: .leading, spacing: 0) {
                    connection
                    detection
                    ZSettingsGroup("存储") { StorageCard(info: storage) }
                    appearance
                    privacy
                }
                .padding(.horizontal, PageMetrics.margin)
                PageFootnote("订阅、节点与流量数据仅保存在此设备上。")
                Text(verbatim: Self.version)
                    .zMono(.small)
                    .foregroundStyle(ZTokens.Colors.screenT3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ZTokens.Space.n6)
            }
            .padding(.bottom, PageMetrics.bottomInset)
        }
        .zPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(store.settings == nil)
        .task { await store.start() }
        .task { storage = await store.engine.storage() }
        .onChange(of: store.lastError) { _, e in
            guard let e else { return }
            toast = ZToastItem(e)
            store.lastError = nil
        }
        .zToast($toast, bottomInset: ZTokens.Space.n6)
        .pageAccent(store.settings)
    }

    // MARK: 连接

    private var connection: some View {
        ZSettingsGroup("连接") {
            ZSettingsRow("按需连接", isOn: store.binding(\.onDemand, fallback: false))
            ZDivider()
            NavigationLink { TrustedWifiView(store: store) } label: {
                ZSettingsRow("受信任的 Wi‑Fi", subtitle: "连接后自动断开",
                             accessory: .valueChevron(store.settings.map(LibraryModel.trustedWifiText) ?? "—"))
            }
            .buttonStyle(ZRowButtonStyle())
            ZDivider()
            NavigationLink { LocalProxyView(store: store) } label: {
                ZSettingsRow("本地代理端口", subtitle: localProxySubtitle, accessory: .chevron)
            }
            .buttonStyle(ZRowButtonStyle())
        }
    }

    private var localProxySubtitle: String? {
        guard let s = store.settings else { return nil }
        return "127.0.0.1:\(s.localProxyPort) · \(s.localProxyAuth ? "需要密码" : "无需密码")"
    }

    // MARK: 检测

    private var detection: some View {
        ZSettingsGroup("检测") {
            ZSettingsRow("仅在 Wi‑Fi 下测速", isOn: store.binding(\.testOnWifiOnly, fallback: true))
            ZDivider()
            MenuPickerRow(title: "结果保留", options: Self.ttlOptions,
                          selection: store.binding(\.latencyTtlHours, fallback: Self.defaultTtl))
        }
    }

    static let defaultTtl: Int32 = 24
    static let ttlOptions: [MenuOption<Int32>] = [6, 12, 24, 72].map { MenuOption(value: Int32($0), title: "\($0) 小时") }

    // MARK: 外观

    private var appearance: some View {
        ZSettingsGroup("外观") {
            MenuPickerRow(title: "外观", options: Self.appearanceOptions,
                          selection: store.binding(\.appearance, fallback: .system))
            ZDivider()
            ZSettingsRow("强调色", trailingIsInteractive: true) {
                AccentPicker(selection: store.binding(\.accent, fallback: .blue))
            }
        }
    }

    static let appearanceOptions: [MenuOption<Appearance>] = [
        MenuOption(value: .system, title: "跟随系统"),
        MenuOption(value: .dark, title: "深色"),
        MenuOption(value: .light, title: "浅色"),
    ]

    // MARK: 隐私

    private var privacy: some View {
        ZSettingsGroup("隐私") {
            ZSettingsRow("分享今日卡片时附带图案", subtitle: "图案由今天的流量生成，不含节点名称与 IP",
                         isOn: store.binding(\.shareAnonymousPattern, fallback: false))
        }
    }

    // MARK: 版本

    /// “Zephyr 1.0 (1)”
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Zephyr \(v) (\(b))"
    }
}

#Preview("设置") {
    NavigationStack { SettingsView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .preferredColorScheme(.dark)
}

#Preview("浅色 · 绿色") {
    NavigationStack { SettingsView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .zAccent(.green)
        .preferredColorScheme(.light)
}

#Preview("大字体 AX5") {
    NavigationStack { SettingsView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.dark)
}

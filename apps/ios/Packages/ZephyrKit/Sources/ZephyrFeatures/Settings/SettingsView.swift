// SettingsView — 设置页（原型 25）。分组：连接 / 检测 / 存储 / 外观 / 隐私；页脚“数据仅保存在此设备上”与版本号。
// 每次改动都经 SettingsStore 全量写回 updateSettings(patch:)；失败回滚并以顶部横幅提示（与首页一致，REVIEW L-P2-11）。
// 强调色与深浅色写回后由 RootView 读取 AppModel.settings 统一应用到整个 App。
// “应用图标”不是引擎设置，走 AppIconModel → UIApplication.setAlternateIconName（REVIEW L-P2-14）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

@MainActor
public struct SettingsView: View {
    @State private var store: SettingsStore
    @State private var icon: AppIconModel
    @State private var storage: StorageInfo?
    /// 被子页（受信任的 Wi‑Fi / 本地代理端口）盖住时不显示横幅，由子页自己显示。
    @State private var isOnTop = true

    public init(engine: any ZephyrEngine) {
        self.init(engine: engine, iconSwitcher: SystemAppIconSwitcher.shared)
    }

    init(engine: any ZephyrEngine, iconSwitcher: any AppIconSwitching) {
        _store = State(initialValue: SettingsStore(engine: engine))
        _icon = State(initialValue: AppIconModel(switcher: iconSwitcher))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "设置", showsNumber: false)
                VStack(alignment: .leading, spacing: 0) {
                    // 设置首帧未到时只禁用依赖设置的分组，页面照常可滚动（REVIEW L-P2-10）。
                    connection.disabled(store.settings == nil)
                    detection.disabled(store.settings == nil)
                    ZSettingsGroup("存储") { StorageCard(info: storage) }
                    appearance
                    privacy.disabled(store.settings == nil)
                }
                .padding(.horizontal, PageMetrics.margin)
                PageFootnote("订阅、节点与流量数据仅保存在此设备上。")
                Text(verbatim: Self.version)
                    .zMono(.small)
                    .foregroundStyle(ZColor.t3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ZTokens.Space.n6)
            }
            .padding(.bottom, PageMetrics.bottomInset)
        }
        .zPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.start() }
        .task { storage = await store.engine.storage() }
        .onAppear { isOnTop = true }
        .onDisappear { isOnTop = false }
        .pageErrorBanner(Bindable(store).lastError, isActive: isOnTop)
        .pageAccent(store.settings)
    }

    // MARK: 连接

    private var connection: some View {
        ZSettingsGroup("连接") {
            ZSettingsRow("按需连接", isOn: store.binding(\.onDemand, fallback: false))
            ZDivider()
            NavigationLink { TrustedWifiView(store: store) } label: {
                ZSettingsRow("受信任的 Wi‑Fi", subtitle: ZL.tr("连接后自动断开"),
                             accessory: .valueChevron(store.settings.map(LibraryModel.trustedWifiText) ?? "—"))
            }
            .buttonStyle(ZRowButtonStyle())
            ZDivider()
            NavigationLink { LocalProxyView(store: store) } label: {
                ZSettingsRow("本地代理端口", subtitle: localProxySubtitle,
                             accessory: .valueChevron(store.settings.map { $0.localProxyEnabled ? ZL.tr("开") : ZL.tr("关") } ?? "—"))
            }
            .buttonStyle(ZRowButtonStyle())
        }
    }

    /// “127.0.0.1:7890 · 需要密码”；行值为开关状态“开 / 关”（原型 settings.png）。
    private var localProxySubtitle: String? {
        guard let s = store.settings else { return nil }
        return "127.0.0.1:\(s.localProxyPort) · \(s.localProxyAuth ? ZL.tr("需要密码") : ZL.tr("无需密码"))"
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
    /// 计算属性而非 static let：按当前 `ZL.bundle` 取文案（快照切语言时不被首次访问缓存成中文）。
    static var ttlOptions: [MenuOption<Int32>] { [6, 12, 24, 72].map { MenuOption(value: Int32($0), title: ZL.f("%lld 小时", Int64($0))) } }

    // MARK: 外观

    private var appearance: some View {
        ZSettingsGroup("外观") {
            MenuPickerRow(title: "外观", options: Self.appearanceOptions,
                          selection: store.binding(\.appearance, fallback: .system))
                .disabled(store.settings == nil)
            ZDivider()
            appIconRow
            ZDivider()
            ZSettingsRow("强调色", trailingIsInteractive: true) {
                AccentPicker(selection: store.binding(\.accent, fallback: .blue))
            }
            .disabled(store.settings == nil)
        }
    }

    /// 原型“应用图标 · 深色 ›”。备用图标资源缺失时只显示当前值、不可点。
    @ViewBuilder private var appIconRow: some View {
        if icon.isSelectable {
            MenuPickerRow(title: "应用图标", options: icon.options.map { MenuOption(value: $0, title: $0.title) },
                          selection: iconSelection)
                .disabled(icon.isChanging)
        } else {
            ZSettingsRow("应用图标", accessory: .value(icon.current.title))
        }
    }

    private var iconSelection: Binding<AppIconOption> {
        Binding(
            get: { icon.current },
            set: { option in
                Task { @MainActor in
                    if let e = await icon.select(option) { store.lastError = e }
                }
            }
        )
    }

    static var appearanceOptions: [MenuOption<Appearance>] {
        [
            MenuOption(value: .system, title: ZL.tr("跟随系统")),
            MenuOption(value: .dark, title: ZL.tr("深色")),
            MenuOption(value: .light, title: ZL.tr("浅色")),
        ]
    }

    // MARK: 隐私

    /// 原型为“共享诊断数据”；契约暂无 shareDiagnostics 字段（NOTES-L），先放“分享今日卡片时附带图案”。
    private var privacy: some View {
        ZSettingsGroup("隐私") {
            ZSettingsRow("分享今日卡片时附带图案", subtitle: ZL.tr("图案由今天的流量生成，不含节点名称与 IP"),
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

#if DEBUG
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
#endif

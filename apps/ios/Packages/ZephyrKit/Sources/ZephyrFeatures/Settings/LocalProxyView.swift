// LocalProxyView — 本地代理端口：开关（契约 §14.z localProxyEnabled）+ 端口号（1024–65535）+ “需要密码”。
// 写回 localProxyEnabled / localProxyPort / localProxyAuth；失败以顶部横幅提示。
// 需要密码时（契约 §16.g ①）：用户名 zephyr、密码（默认遮挡，点按显示）、复制 HTTP / SOCKS5 地址（敏感剪贴板）、
// 重新生成密码（引擎在隧道运行且需要密码时热重载）。凭据来自 engine.localProxyCredential()，与隧道配置同一个。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

@MainActor
struct LocalProxyView: View {
    let store: SettingsStore
    @State private var portText = ""
    @State private var credential: LocalProxyCredentialModel
    @State private var confirmingReset = false
    @State private var toast: ZToastItem?

    init(store: SettingsStore) {
        self.store = store
        _credential = State(initialValue: LocalProxyCredentialModel(engine: store.engine))
    }

    static let validPorts: ClosedRange<Int32> = 1024...65535

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZSettingsGroup(footer: "开启后仅监听 127.0.0.1，局域网中的其他设备无法连接。") {
                    ZSettingsRow("本地代理端口", isOn: store.binding(\.localProxyEnabled, fallback: false))
                }
                ZSettingsGroup("端口", footer: "其他 App 可通过 127.0.0.1 上的这个端口使用 Zephyr 的规则与场景。") {
                    ZTextField("7890", text: $portText, systemImage: "number", style: .plain, monospaced: true, onSubmit: { save() })
                        .keyboardType(.numberPad)
                    if let invalid {
                        ZDivider()
                        Text(verbatim: invalid)
                            .zType(.footnote)
                            .foregroundStyle(ZTokens.Colors.screenAmber)
                            .padding(.horizontal, ZTokens.Space.n5)
                            .padding(.vertical, ZTokens.Space.n3)
                    }
                }
                ZSettingsGroup("安全", footer: "开启后，连接本地端口需要用户名与密码，可防止其他 App 未经允许使用代理。") {
                    ZSettingsRow("需要密码", isOn: store.binding(\.localProxyAuth, fallback: false))
                    if requiresPassword {
                        ZDivider()
                        ZSettingsRow("用户名", accessory: .value(credential.username))
                        ZDivider()
                        passwordRow
                    }
                }
                if requiresPassword {
                    ZSettingsGroup(footer: "重新生成后，其他 App 中填写的旧密码将失效。") {
                        copyRow("复制 HTTP 地址", .http)
                        ZDivider()
                        copyRow("复制 SOCKS5 地址", .socks5)
                        ZDivider()
                        Button { confirmingReset = true } label: {
                            ZSettingsRow("重新生成密码", accessory: .none)
                        }
                        .buttonStyle(ZRowButtonStyle())
                        .disabled(credential.credential == nil || credential.isResetting)
                    }
                }
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.bottom, PageMetrics.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .zPageBackground()
        .navigationTitle(Text("本地代理端口"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Text("存储") }
                    .disabled(parsed == nil || parsed == store.settings?.localProxyPort)
            }
        }
        .pageErrorBanner(Bindable(store).lastError)
        .zToast($toast, bottomInset: ZTokens.Space.n6)
        .confirmationDialog(Text("重新生成密码"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(role: .destructive) {
                Task {
                    await credential.reset()
                    toast = ZToastItem(ZL.tr("已生成新密码"))
                }
            } label: { Text("重新生成密码") }
            Button(role: .cancel) {} label: { Text("取消") }
        } message: {
            Text("重新生成后，其他 App 中填写的旧密码将失效。")
        }
        .task { await credential.load() }
        .onAppear { if let p = store.settings?.localProxyPort { portText = String(p) } }
        .onChange(of: store.settings?.localProxyPort) { _, p in
            if let p { portText = String(p) }
        }
    }

    private var requiresPassword: Bool { store.settings?.localProxyAuth == true }

    private var port: Int32 { store.settings?.localProxyPort ?? 7890 }

    /// 密码行：点按在遮挡 / 明文间切换；VoiceOver 读“显示密码 / 隐藏密码”，明文时读出密码。
    private var passwordRow: some View {
        Button { credential.isRevealed.toggle() } label: {
            ZSettingsRow("密码") {
                HStack(spacing: ZTokens.Space.n2) {
                    Text(verbatim: credential.displayedPassword)
                        .zMono(.small)
                        .foregroundStyle(ZColor.t3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textSelection(.disabled)
                    Image(systemName: credential.isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(ZColor.t3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(ZRowButtonStyle())
        .disabled(credential.credential == nil)
        .accessibilityLabel(Text(credential.isRevealed ? "隐藏密码" : "显示密码"))
        .accessibilityValue(Text(verbatim: credential.isRevealed ? (credential.password ?? "") : ""))
    }

    private func copyRow(_ title: LocalizedStringKey, _ scheme: LocalProxyCredential.Scheme) -> some View {
        Button {
            if credential.copy(scheme, port: port) { toast = ZToastItem(ZL.tr("已复制，60 秒后从剪贴板清除")) }
        } label: {
            ZSettingsRow(title, subtitle: credential.displayedURL(scheme, port: port), accessory: .none)
        }
        .buttonStyle(ZRowButtonStyle())
        .disabled(credential.credential == nil)
    }

    private var parsed: Int32? {
        guard let v = Int32(portText.trimmingCharacters(in: .whitespaces)), Self.validPorts.contains(v) else { return nil }
        return v
    }

    private var invalid: String? {
        guard !portText.isEmpty, parsed == nil else { return nil }
        return ZL.f("请输入 %d–%d 之间的端口", Self.validPorts.lowerBound, Self.validPorts.upperBound)
    }

    private func save() {
        guard let p = parsed else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { await store.update { $0.localProxyPort = p } }
    }
}

#if DEBUG
#Preview {
    let store = SettingsStore(engine: MockEngine(seed: 0, clock: .frozen941))
    return NavigationStack { LocalProxyView(store: store) }
        .task { await store.start() }
        .preferredColorScheme(.dark)
}
#endif

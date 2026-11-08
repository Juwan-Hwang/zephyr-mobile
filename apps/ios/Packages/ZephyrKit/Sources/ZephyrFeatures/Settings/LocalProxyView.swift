// LocalProxyView — 本地代理端口：开关（契约 §14.z localProxyEnabled）+ 端口号（1024–65535）+ “需要密码”。
// 写回 localProxyEnabled / localProxyPort / localProxyAuth；失败以顶部横幅提示。
// 凭据（zephyr:<24 位随机>）由 CoreEngine.localProxyCredential() 生成，不在 ZephyrEngine 协议里，暂不展示（NOTES-L）。

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
                }
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.bottom, PageMetrics.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .zPageBackground()
        .navigationTitle(Text(verbatim: "本地代理端口"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Text(verbatim: "存储") }
                    .disabled(parsed == nil || parsed == store.settings?.localProxyPort)
            }
        }
        .pageErrorBanner(Bindable(store).lastError)
        .onAppear { if let p = store.settings?.localProxyPort { portText = String(p) } }
        .onChange(of: store.settings?.localProxyPort) { _, p in
            if let p { portText = String(p) }
        }
    }

    private var parsed: Int32? {
        guard let v = Int32(portText.trimmingCharacters(in: .whitespaces)), Self.validPorts.contains(v) else { return nil }
        return v
    }

    private var invalid: String? {
        guard !portText.isEmpty, parsed == nil else { return nil }
        return "请输入 \(Self.validPorts.lowerBound)–\(Self.validPorts.upperBound) 之间的端口"
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

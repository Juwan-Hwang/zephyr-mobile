// TrustedWifiView — 受信任的 Wi‑Fi：开关“连上这些 Wi‑Fi 时自动断开” + 名称列表（左滑删除）+ 手动添加。
// 写回 Settings.trustedWifi / disconnectOnTrusted（全量 updateSettings）。
// 读取当前 Wi‑Fi 名称需要 NEHotspotNetwork + 定位授权（App 层能力），此处只支持手动输入（见 NOTES-L）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

@MainActor
struct TrustedWifiView: View {
    let store: SettingsStore
    @State private var name = ""

    var body: some View {
        List {
            Section {
                ZSettingsRow("连上这些 Wi‑Fi 时自动断开", isOn: store.binding(\.disconnectOnTrusted, fallback: false))
                    .zCardListRow()
            } footer: {
                footnote("在家或公司等可信网络中，Zephyr 会自动断开，离开后按需重新连接。")
            }
            Section {
                ForEach(names, id: \.self) { ssid in
                    ZSettingsRow(verbatim: ssid, accessory: .none)
                        .zCardListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { remove(ssid) } label: {
                                Label { Text(verbatim: "删除") } icon: { Image(systemName: "trash") }
                            }
                            .tint(ZTokens.Colors.screenRed)
                        }
                        .accessibilityAction(named: Text(verbatim: "删除")) { remove(ssid) }
                }
                ZTextField("添加 Wi‑Fi 名称", text: $name, systemImage: "wifi", style: .plain, onSubmit: { add() })
                    .zCardListRow()
            } header: {
                ZSectionHeader("网络", trailing: names.isEmpty ? nil : "\(names.count) 个")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, PageMetrics.margin, for: .scrollContent)
        .zPageBackground()
        .navigationTitle(Text(verbatim: "受信任的 Wi‑Fi"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { add() } label: { Text(verbatim: "添加") }
                    .disabled(trimmed.isEmpty || names.contains(trimmed))
            }
        }
    }

    private var names: [String] { store.settings?.trustedWifi ?? [] }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        let ssid = trimmed
        guard !ssid.isEmpty, !names.contains(ssid) else { return }
        name = ""
        Task { await store.update { $0.trustedWifi.append(ssid) } }
    }

    private func remove(_ ssid: String) {
        Task { await store.update { $0.trustedWifi.removeAll { $0 == ssid } } }
    }

    private func footnote(_ s: String) -> some View {
        Text(verbatim: s).zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
    }
}

#Preview {
    let store = SettingsStore(engine: MockEngine(seed: 0, clock: .frozen941))
    return NavigationStack { TrustedWifiView(store: store) }
        .task { await store.start() }
        .preferredColorScheme(.dark)
}

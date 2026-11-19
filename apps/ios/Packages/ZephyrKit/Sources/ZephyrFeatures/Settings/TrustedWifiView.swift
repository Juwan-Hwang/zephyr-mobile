// TrustedWifiView — 受信任的 Wi‑Fi：开关“连上这些 Wi‑Fi 时自动断开” + 名称列表（左滑删除）+ 手动添加。
// 写回 Settings.trustedWifi / disconnectOnTrusted（全量 updateSettings）。
// 输入按契约 §16.c 校验（TrustedWifi.check：1–32 字节 UTF‑8、去重、≤ 50 项），超长 / 已满时禁用“添加”并在输入框下说明原因。
// 读取当前 Wi‑Fi 名称需要 NEHotspotNetwork + 定位授权（App 层能力），此处只支持手动输入（见 NOTES-L）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

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
                footnote(ZL.tr("在家或公司等可信网络中，Zephyr 会自动断开，离开后按需重新连接。"))
            }
            Section {
                ForEach(names, id: \.self) { ssid in
                    ZSettingsRow(verbatim: ssid, accessory: .none)
                        .zCardListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { remove(ssid) } label: {
                                Label { Text("删除") } icon: { Image(systemName: "trash") }
                            }
                            .tint(ZTokens.Colors.screenRed)
                        }
                        .accessibilityAction(named: Text("删除")) { remove(ssid) }
                }
                ZTextField("添加 Wi‑Fi 名称", text: $name, systemImage: "wifi", style: .plain, onSubmit: { add() })
                    .zCardListRow()
            } header: {
                // 去掉 insetGrouped 自带的页眉内边距，标题与卡片左缘按原型对齐（同 REVIEW L-P2-12）。
                ZSectionHeader("网络", trailing: names.isEmpty ? nil : ZL.f("%lld 个", Int64(names.count)))
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            } footer: {
                if let hint = inputHint { footnote(hint) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, PageMetrics.margin, for: .scrollContent)
        .zPageBackground()
        .pageErrorBanner(Bindable(store).lastError)
        .navigationTitle(Text("受信任的 Wi‑Fi"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { add() } label: { Text("添加") }
                    .disabled(candidate == nil)
            }
        }
    }

    private var names: [String] { store.settings?.trustedWifi ?? [] }
    private var check: TrustedWifi.Check { TrustedWifi.check(name, existing: names) }

    /// 可以添加的名称（已去首尾空白）；不可添加为 nil。
    private var candidate: String? {
        if case .ok(let ssid) = check { return ssid }
        return nil
    }

    /// 输入框下的原因说明：只对用户需要知道的两种情况（超长 / 已满）提示，空与重复只禁用按钮。
    private var inputHint: String? {
        switch check {
        case .tooLong: ZL.tr("Wi‑Fi 名称不能超过 32 字节")
        case .full: ZL.tr("最多添加 50 个 Wi‑Fi")
        case .ok, .empty, .duplicate: nil
        }
    }

    private func add() {
        guard let ssid = candidate else { return }
        name = ""
        Task { await store.update { $0.trustedWifi.append(ssid) } }
    }

    private func remove(_ ssid: String) {
        Task { await store.update { $0.trustedWifi.removeAll { $0 == ssid } } }
    }

    private func footnote(_ s: String) -> some View {
        Text(verbatim: s).zType(.footnote).foregroundStyle(ZColor.t3)
    }
}

#if DEBUG
#Preview {
    let store = SettingsStore(engine: MockEngine(seed: 0, clock: .frozen941))
    return NavigationStack { TrustedWifiView(store: store) }
        .task { await store.start() }
        .preferredColorScheme(.dark)
}
#endif

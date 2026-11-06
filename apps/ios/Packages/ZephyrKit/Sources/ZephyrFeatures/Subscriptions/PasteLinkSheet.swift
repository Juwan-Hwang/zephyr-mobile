// PasteLinkSheet — 粘贴订阅链接。系统 PasteButton 读剪贴板（不触发“允许粘贴”弹窗），也可手动输入。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

struct PasteLinkSheet: View {
    let importer: SubscriptionImporter
    var onImported: (Subscription) -> Void
    @State private var link = ""
    /// 最近一次从剪贴板粘贴的内容；与输入框一致时按 clipboard 来源导入。
    @State private var pasted: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ZTokens.Space.n4) {
                TextField("https://", text: $link, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                    .padding(ZTokens.Space.n4)
                    .lCard(radius: ZTokens.Radius.surface)
                PasteButton(payloadType: String.self) { strings in
                    guard let s = strings.first else { return }
                    Task { @MainActor in
                        pasted = s
                        link = s
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                if let err = importer.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .zType(.footnote)
                        .foregroundStyle(ZTokens.Colors.textWarning)
                }
                Text("订阅与流量数据仅保存在此设备上。")
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(LStyle.margin)
            .background(LStyle.pageBackground)
            .navigationTitle("粘贴链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if importer.isImporting {
                        ProgressView()
                    } else {
                        Button("导入") { submit() }
                            .fontWeight(.semibold)
                            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { importer.reset(); focused = true }
    }

    private func submit() {
        Task {
            if let sub = await importer.importLink(link, fromClipboard: link == pasted) {
                onImported(sub)
                dismiss()
            }
        }
    }
}

#Preview {
    PasteLinkSheet(importer: SubscriptionImporter(engine: MockEngine(seed: 0, clock: .frozen941)), onImported: { _ in })
}

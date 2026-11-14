// RuleAddSheet — 规则页右上角“+”：添加覆写（域名 → 直连 / 某个场景）。
// 经 engine.overrideHost(host, target, sceneId, persistent: true) 写入第 1 层（契约 §13）；订阅更新时保持不变。
// 覆写按域名生效（含子域名），关键词 / IP 段此版本不支持，输入框校验会提示。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

struct RuleAddSheet: View {
    let engine: any ZephyrEngine
    let onAdded: () -> Void

    @State private var target = ""
    @State private var choice: Choice = .direct
    @State private var scenes: [ZephyrKit.Scene] = []
    @State private var busy = false
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    enum Choice: Hashable { case direct, scene(String) }

    /// 分段最多 4 项（直连 + 3 个场景），再多挤得点不准。
    private static let maxScenes = 3

    /// 规范化输入：去空白、去协议与路径、转小写、去端口；不合法返回 nil。
    static func normalizedHost(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { s = String(s[..<slash]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":"), !s.contains("]"), s.filter({ $0 == ":" }).count == 1 { s = String(s[..<colon]) }
        while s.hasSuffix(".") { s.removeLast() }
        guard !s.isEmpty, s.count <= 253, !s.contains(" ") else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-._*:[]")
        guard s.allSatisfy({ allowed.contains($0) || !$0.isASCII }) else { return nil }
        return s
    }

    private var host: String? { Self.normalizedHost(target) }

    private var segments: [ZSegment<Choice>] {
        var out = [ZSegment(Choice.direct, verbatim: ZL.tr("直连"))]
        for s in scenes.prefix(Self.maxScenes) { out.append(ZSegment(.scene(s.id), verbatim: s.name)) }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ZTextField("域名，例如 example.com", text: $target, systemImage: nil, monospaced: true)
                    .padding(.top, ZTokens.Space.n5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                ZSectionHeader("使用")
                ZSegmented(segments, selection: $choice, label: "使用")
                if let errorText {
                    Text(verbatim: errorText)
                        .zType(.footnote)
                        .foregroundStyle(ZTokens.Colors.screenRed)
                        .padding(.horizontal, ZTokens.Space.n2)
                        .padding(.top, ZTokens.Space.n3)
                        .accessibilityLabel(Text(verbatim: errorText))
                }
                Text("覆写位于第 1 层，在订阅规则之上，订阅更新时保持不变。按域名生效，包含子域名。")
                    .zType(.footnote)
                    .foregroundStyle(ZColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ZTokens.Space.n2)
                    .padding(.top, ZTokens.Space.n4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PageMetrics.margin)
            .zPageBackground()
            .navigationTitle(Text("添加覆写"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("取消") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { add() } label: { Text("添加") }
                        .disabled(host == nil || busy)
                }
            }
            .onChange(of: target) { errorText = nil }
            .task {
                for await list in engine.scenes() { scenes = list; break }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        guard let host, !busy else { return }
        busy = true
        var kind = TraceTarget.direct
        var sceneId: String?
        if case .scene(let id) = choice { kind = .scene; sceneId = id }
        Task {
            do {
                try await engine.overrideHost(host: host, target: kind, sceneId: sceneId, persistent: true)
                busy = false
                onAdded()
                dismiss()
            } catch {
                busy = false
                errorText = (error as? ZephyrError)?.userMessage ?? ZephyrError(code: .internal, message: "").userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    RuleAddSheet(engine: MockEngine(seed: 0, clock: .frozen941), onAdded: {})
        .preferredColorScheme(.dark)
}
#endif

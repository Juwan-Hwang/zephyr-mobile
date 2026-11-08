// OnboardingView — 第一次打开（原型 01 / 02）。
//   1 / 2 添加订阅：粘贴链接 / 扫描二维码 / 从电脑上的 Zephyr 导入 / 从文件导入（复用 SubscriptionImportFlow）
//   2 / 2 已添加 Nebula Cloud（312 个节点）· 选择使用方式：简单 / 优选（默认）→ 继续
// 继续 → onFinish()（或 onFinishChoosing(choice)）。“优选”同时写回 testOnWifiOnly = true（“每天在 Wi‑Fi 下检测节点”）。
// 原型 03（连接 / VPN 授权）由宿主在 onFinish 后展示首页未连接态完成。

import SwiftUI
import ZephyrDesign
import ZephyrKit
import ZephyrMock

/// 引导第 2 步的选择。
public enum OnboardingChoice: String, Sendable, Hashable, CaseIterable {
    /// 使用订阅提供的分组（场景来源 = subscription_group）。
    case simple
    /// Zephyr 优选（场景来源 = auto）。
    case best
}

@MainActor
public struct OnboardingView: View {
    @State private var importer: SubscriptionImporter
    @State private var store: SettingsStore
    @State private var method: SubscriptionImportMethod?
    @State private var added: Subscription?
    @State private var choice: OnboardingChoice = .best
    @State private var finishing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var markHeight: CGFloat = ZTokens.Space.n7 - ZTokens.Space.n1 / 2
    private let onFinish: (OnboardingChoice) -> Void

    /// 完成后回调（选择已写回设置；宿主只需切到首页）。
    public init(engine: any ZephyrEngine, onFinish: @escaping () -> Void) {
        self.init(engine: engine, added: nil) { _ in onFinish() }
    }

    /// 需要知道用户选了“简单 / 优选”时用这个（例如 App 层据此设置场景来源，见 NOTES-L）。
    public init(engine: any ZephyrEngine, onFinishChoosing: @escaping (OnboardingChoice) -> Void) {
        self.init(engine: engine, added: nil, onFinish: onFinishChoosing)
    }

    /// 预览 / 快照：直接从第 2 步开始。
    init(engine: any ZephyrEngine, added: Subscription?, onFinish: @escaping (OnboardingChoice) -> Void) {
        _importer = State(initialValue: SubscriptionImporter(engine: engine))
        _store = State(initialValue: SettingsStore(engine: engine))
        _added = State(initialValue: added)
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            if let added {
                chooseStep(added)
                    .transition(transition)
            } else {
                importStep
                    .transition(transition)
            }
        }
        .animation(ZMotion.gentle(ZMotion.page, reduceMotion: reduceMotion), value: added?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zPageBackground()
        .subscriptionImportFlow(method: $method, importer: importer) { sub in added = sub }
        .task { await store.start() }
        .pageAccent(store.settings)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: 1 / 2 添加订阅

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZBrandMark(.mark)
                        .frame(height: markHeight)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                        .padding(.top, ZTokens.Space.n5)
                    stepLabel("1 / 2").padding(.top, ZTokens.Space.n8 + ZTokens.Space.n4)
                    title("添加订阅")
                    SubscriptionImportOptions { method = $0 }
                        .disabled(importer.isImporting)
                        .padding(.top, ZTokens.Space.n6)
                    status
                }
                .padding(.horizontal, ZTokens.Space.n6)
            }
            .scrollBounceBehavior(.basedOnSize)
            footnote("订阅与流量数据仅保存在此设备上。")
        }
    }

    @ViewBuilder private var status: some View {
        if importer.isImporting {
            HStack(spacing: ZTokens.Space.n3) {
                ProgressView()
                Text(verbatim: "正在导入…").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
            }
            .padding(.top, ZTokens.Space.n4)
        } else if method == nil, let err = importer.errorMessage {
            Label { Text(verbatim: err) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenAmber)
                .padding(.top, ZTokens.Space.n4)
        }
    }

    // MARK: 2 / 2 选择使用方式

    private func chooseStep(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stepLabel("2 / 2").padding(.top, ZTokens.Space.n8)
                    HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(ZTokens.Colors.textOnAccent, ZSwitchColor.on)
                            .accessibilityHidden(true)
                        Text(verbatim: "已添加 \(sub.name)（\(ZFormat.count(sub.nodeCount)) 个节点）")
                            .zType(.body)
                            .foregroundStyle(ZTokens.Colors.screenT2)
                    }
                    .padding(.top, ZTokens.Space.n6)
                    title("选择\n使用方式")
                    VStack(spacing: ZTokens.Space.n4) {
                        OnboardingChoiceCard(title: "简单", detail: "使用订阅提供的分组。节点不可用时自动处理。",
                                             isOn: choice == .simple) { choice = .simple }
                        OnboardingChoiceCard(title: "优选", detail: "每天在 Wi‑Fi 下检测节点。AI 与视频仅使用检测通过的节点。每次约 3 MB。",
                                             isOn: choice == .best) { choice = .best }
                    }
                    .padding(.top, ZTokens.Space.n4)
                }
                .padding(.horizontal, ZTokens.Space.n6)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 0) {
                ZButton("继续", kind: .primary, size: .large, fullWidth: true, isLoading: finishing) { finish() }
                    .padding(.horizontal, ZTokens.Space.n6)
                footnote("可随时在设置中更改。")
            }
        }
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        let c = choice
        Task {
            if c == .best { await store.update { $0.testOnWifiOnly = true } }
            finishing = false
            onFinish(c)
        }
    }

    // MARK: 共用

    private func stepLabel(_ s: String) -> some View {
        Text(verbatim: s)
            .zMono(.body)
            .foregroundStyle(ZTokens.Colors.screenT3)
            .accessibilityLabel(Text(verbatim: "第 \(s.prefix(1)) 步，共 2 步"))
    }

    private func title(_ s: String) -> some View {
        Text(verbatim: s)
            .font(.system(size: 34, weight: .light))
            .lineSpacing(6)
            .foregroundStyle(ZTokens.Colors.screenT1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, ZTokens.Space.n3)
            .accessibilityAddTraits(.isHeader)
    }

    private func footnote(_ s: String) -> some View {
        Text(verbatim: s)
            .zType(.footnote)
            .foregroundStyle(ZTokens.Colors.screenT3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, ZTokens.Space.n4)
            .padding(.bottom, ZTokens.Space.n3)
    }
}

#Preview("1 / 2 添加订阅") {
    OnboardingView(engine: MockEngine(seed: 0, clock: .frozen941)) {}
        .preferredColorScheme(.dark)
}

#Preview("2 / 2 选择使用方式") {
    OnboardingView(engine: MockEngine(seed: 0, clock: .frozen941),
                   added: Subscription(id: "nebula", name: "Nebula Cloud", nodeCount: 312, autoUpdateHours: 12)) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("浅色 · AX5") {
    OnboardingView(engine: MockEngine(seed: 0, clock: .frozen941)) {}
        .zAccent(.orange)
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.light)
}

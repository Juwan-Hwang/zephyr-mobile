// 吐司（原型 `.toast`：52 高、圆角 18、--s4 底、14 号字；右侧强调色动作 “撤销”；底部 2pt 强调色进度条线性耗尽）。
// 停留时长默认 ZTokens.Motion.undoWindow（4s）。出现时 VoiceOver 播报；Reduce Motion 下只淡入淡出。

import SwiftUI

public struct ZToastItem: Identifiable, Equatable {
    public let id: UUID
    public var message: String
    public var actionTitle: String?
    public var duration: TimeInterval
    public var action: (() -> Void)?

    /// 例：`ZToastItem("已换到 东京 03", actionTitle: "撤销") { model.undo() }`
    public init(_ message: String,
                actionTitle: String? = nil,
                duration: TimeInterval = ZTokens.Motion.undoWindow,
                action: (() -> Void)? = nil) {
        self.id = UUID()
        self.message = message
        self.actionTitle = actionTitle
        self.duration = duration
        self.action = action
    }

    public static func == (lhs: ZToastItem, rhs: ZToastItem) -> Bool { lhs.id == rhs.id }
}

/// 吐司本体（一般通过 `.zToast($item)` 使用）。
public struct ZToast: View {
    private let item: ZToastItem
    private let onDismiss: () -> Void
    @State private var remaining: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = ZMetrics.toastHeight

    public init(_ item: ZToastItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZMetrics.toastRadius, style: .continuous)
        HStack(spacing: ZTokens.Space.n3) {
            Text(verbatim: item.message)
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let title = item.actionTitle {
                Button {
                    item.action?()
                    onDismiss()
                } label: {
                    Text(verbatim: title)
                        .zType(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(ZAccentStyle())
                        .padding(.horizontal, ZTokens.Space.n4)
                        .frame(minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .none))
            }
        }
        .padding(.leading, ZTokens.Space.n5)
        .padding(.trailing, ZTokens.Space.n2)
        .padding(.vertical, ZTokens.Space.n1)
        .frame(minHeight: height)
        .background(shape.fill(ZTokens.Colors.screenS4))
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(ZAccentStyle())
                .frame(height: ZMetrics.toastDrain)
                .scaleEffect(x: remaining, y: 1, anchor: .leading)
                .accessibilityHidden(true)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(ZTokens.Colors.screenHl, lineWidth: ZMetrics.hairline) }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.linear(duration: item.duration)) { remaining = 0 }
            AccessibilityNotification.Announcement(item.message).post()
        }
    }
}

public extension View {
    /// 在底部（指令栏上方）显示吐司；到时自动消失。设置新的 item 会替换旧的并重新计时。
    func zToast(_ item: Binding<ZToastItem?>, bottomInset: CGFloat = ZMetrics.dockHeight + ZTokens.Space.n4) -> some View {
        modifier(ZToastPresenter(item: item, bottomInset: bottomInset))
    }
}

private struct ZToastPresenter: ViewModifier {
    @Binding var item: ZToastItem?
    let bottomInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let current = item {
                        ZToast(current) { item = nil }
                            .id(current.id)
                            .padding(.horizontal, ZTokens.Space.n4)
                            .padding(.bottom, bottomInset)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(ZMotion.gentle(ZMotion.slow, reduceMotion: reduceMotion), value: item?.id)
            }
            .task(id: item?.id) {
                guard let current = item else { return }
                try? await Task.sleep(for: .seconds(current.duration))
                guard !Task.isCancelled, item?.id == current.id else { return }
                item = nil
            }
    }
}

#if DEBUG
private struct ZToastSample: View {
    @State var item: ZToastItem? = ZToastItem("已换到 东京 03", actionTitle: "撤销", duration: 600)
    var scheme: ColorScheme = .dark
    var body: some View {
        VStack {
            ZButton("再来一次") { item = ZToastItem("已换到 东京 03", actionTitle: "撤销") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zPageBackground()
        .zToast($item)
        .preferredColorScheme(scheme)
    }
}
#endif

#Preview("深色") { ZToastSample() }
#Preview("浅色") { ZToastSample(scheme: .light) }
#Preview("强调色") { ZToastSample().zAccent(.pink) }
#Preview("AX5") { ZToastSample().dynamicTypeSize(.accessibility5) }

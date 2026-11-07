// Sheet 样式（原型 `.sheet`：顶部抓手 36×5、标题 17/500 + 右侧 “完成”、正文可滚动、顶部 1px 细边框）。
// 两部分：
//   ZSheet { … }                 sheet 内部的版式（抓手 + 标题栏 + 内容）
//   .zSheet(isPresented:) { … }  呈现：detents、圆角 ZTokens.Layout.sheetRadius、背景 screen.s1、强调色透传
// “完成”默认调用 `dismiss`。

import SwiftUI

public struct ZSheet<Accessory: View, Content: View>: View {
    private let title: LocalizedStringKey
    private let doneTitle: LocalizedStringKey?
    private let onDone: (() -> Void)?
    private let scrolls: Bool
    private let accessory: Accessory
    private let content: Content
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - doneTitle: 右上角按钮文字；传 nil 不显示。
    ///   - onDone: 点 “完成” 的动作；默认关闭 sheet。
    ///   - scrolls: 内容是否包在 ScrollView 里（列表类内容自己管理滚动时传 false）。
    ///   - accessory: 标题右侧、“完成”左侧的附加控件（如 “检测” 按钮）。
    public init(_ title: LocalizedStringKey,
                doneTitle: LocalizedStringKey? = "完成",
                onDone: (() -> Void)? = nil,
                scrolls: Bool = true,
                @ViewBuilder accessory: () -> Accessory,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.doneTitle = doneTitle
        self.onDone = onDone
        self.scrolls = scrolls
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(ZQuaternaryText())
                .frame(width: ZMetrics.grabberWidth, height: ZMetrics.grabberHeight)
                .padding(.top, ZTokens.Space.n3)
                .accessibilityHidden(true)
            header
            if scrolls {
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollIndicators(.hidden)
            } else {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .environment(\.zInSheet, true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
            Text(title)
                .zType(.headline)
                .fontWeight(.medium)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: ZTokens.Space.n3)
            accessory
            if let doneTitle {
                Button {
                    if let onDone { onDone() } else { dismiss() }
                } label: {
                    Text(doneTitle)
                        .zType(.body)
                        .foregroundStyle(ZTokens.Colors.screenT2)
                        .frame(minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .none))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }
}

public extension ZSheet where Accessory == EmptyView {
    init(_ title: LocalizedStringKey,
         doneTitle: LocalizedStringKey? = "完成",
         onDone: (() -> Void)? = nil,
         scrolls: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.init(title, doneTitle: doneTitle, onDone: onDone, scrolls: scrolls, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - 呈现

public extension View {
    /// 以 Zephyr 样式呈现 sheet。内容通常是 `ZSheet("场景") { … }`。
    func zSheet<Content: View>(isPresented: Binding<Bool>,
                               detents: Set<PresentationDetent> = [.large],
                               onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(ZSheetPresenter(isPresented: isPresented, detents: detents, onDismiss: onDismiss, sheet: content))
    }

    /// 只套用 Zephyr 的 presentation 外观（给自行 `.sheet(item:)` 的调用方）。
    func zSheetPresentation(detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(ZTokens.Layout.sheetRadius)
            .presentationBackground(ZTokens.Colors.screenS1)
            .environment(\.zInSheet, true)
    }
}

private struct ZSheetPresenter<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let detents: Set<PresentationDetent>
    let onDismiss: (() -> Void)?
    let sheet: () -> Sheet
    @Environment(\.zAccent) private var accent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            sheet()
                .zAccent(accent)
                .zSheetPresentation(detents: detents)
        }
    }
}

#if DEBUG
private struct ZSheetSample: View {
    @State var shown = true
    var scheme: ColorScheme = .dark
    var body: some View {
        Color.clear
            .zSheet(isPresented: $shown) {
                ZSheet("场景") {
                    VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                        ZBigNumber("9", unit: "个可用", size: .hero)
                        Text(verbatim: "从 13,109,802 个节点中筛选").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
                    }
                    .padding(.horizontal, ZTokens.Space.n6)
                    .padding(.top, ZTokens.Space.n5)
                }
                .preferredColorScheme(scheme)
            }
            .zPageBackground()
            .preferredColorScheme(scheme)
    }
}
#endif

#Preview("深色") { ZSheetSample() }
#Preview("浅色") { ZSheetSample(scheme: .light) }
#Preview("强调色") { ZSheetSample().zAccent(.orange) }
#Preview("AX5") { ZSheetSample().dynamicTypeSize(.accessibility5) }

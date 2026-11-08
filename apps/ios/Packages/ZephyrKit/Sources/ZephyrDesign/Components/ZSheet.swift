// Sheet 样式（原型 `.sheet`：顶部抓手 36×5、标题 17/500 + 右侧 “完成”、正文可滚动、顶部 1px 细边框）。
// 两部分：
//   ZSheet { … }                 sheet 内部的版式（抓手 + 标题栏 + 内容）
//   .zSheet(isPresented:) { … }  呈现：detents、圆角 ZTokens.Layout.sheetRadius、背景 screen.s1、强调色透传
// “完成”默认调用 `dismiss`。
// 标题：UI 文案用 `ZSheet("场景")`（LocalizedStringKey）；用户数据（场景名、订阅名）用 `ZSheet(verbatim: scene.name)`，不进本地化查表。

import SwiftUI

public struct ZSheet<Accessory: View, Content: View>: View {
    private let title: Text
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
        self.init(title: Text(title), doneTitle: doneTitle, onDone: onDone, scrolls: scrolls,
                  accessory: accessory(), content: content())
    }

    /// 标题为用户数据（如场景名 `scene.name`）时用：原样显示，不做本地化查表。
    public init(verbatim title: String,
                doneTitle: LocalizedStringKey? = "完成",
                onDone: (() -> Void)? = nil,
                scrolls: Bool = true,
                @ViewBuilder accessory: () -> Accessory,
                @ViewBuilder content: () -> Content) {
        self.init(title: Text(verbatim: title), doneTitle: doneTitle, onDone: onDone, scrolls: scrolls,
                  accessory: accessory(), content: content())
    }

    private init(title: Text,
                 doneTitle: LocalizedStringKey?,
                 onDone: (() -> Void)?,
                 scrolls: Bool,
                 accessory: Accessory,
                 content: Content) {
        self.title = title
        self.doneTitle = doneTitle
        self.onDone = onDone
        self.scrolls = scrolls
        self.accessory = accessory
        self.content = content
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
            title
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
                        .foregroundStyle(ZColor.t2)
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

    /// 标题为用户数据时用（见 `init(verbatim:accessory:content:)`）。
    init(verbatim title: String,
         doneTitle: LocalizedStringKey? = "完成",
         onDone: (() -> Void)? = nil,
         scrolls: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.init(verbatim: title, doneTitle: doneTitle, onDone: onDone, scrolls: scrolls, accessory: { EmptyView() }, content: content)
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
            .presentationBackground { ZSheetBackground() }
            .environment(\.zInSheet, true)
    }
}

/// sheet 背景：--s1 + 跟随顶部 34pt 圆角的 1px --hl2 细边（原型 `.sheet{border-top:1px solid var(--hl2)}`）。
/// 细边沿两侧圆角收尾，不再是被圆角裁断的直线。
private struct ZSheetBackground: View {
    var body: some View {
        ZTokens.Colors.screenS1
            .overlay(alignment: .top) {
                ZSheetTopEdge(radius: ZTokens.Layout.sheetRadius)
                    .stroke(ZTokens.Colors.screenHl2, lineWidth: ZMetrics.hairline)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// 只有顶边：左侧圆角弧 → 顶边直线 → 右侧圆角弧（开放路径，描边内收半个线宽避免被裁一半）。
private struct ZSheetTopEdge: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = ZMetrics.hairline / 2
        let r = max(0, min(radius, rect.width / 2) - inset)
        let minX = rect.minX + inset, maxX = rect.maxX - inset, minY = rect.minY + inset
        var p = Path()
        p.move(to: CGPoint(x: minX, y: minY + r))
        p.addArc(center: CGPoint(x: minX + r, y: minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: maxX - r, y: minY))
        p.addArc(center: CGPoint(x: maxX - r, y: minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        return p
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
                        Text(verbatim: "从 13,109,802 个节点中筛选").zType(.footnote).foregroundStyle(ZColor.t3)
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

// 分段控件（原型 `.seg`：底 --s3、圆角 13、内边距 3、文字 13.5 t2 / 选中 t1；滑块 --s4 圆角 10、阴影 0 2 6 rgba(0,0,0,.4)，
// 320ms cubic-bezier(.16,1,.3,1) 滑动）。
// 用于场景 sheet “订阅分组 | Zephyr 优选”、连接轨迹 “不变 / 直连 / 视频 / 其他”。
// 切换给 selection 触感；Reduce Motion 下滑块直接跳位。AX 大字体且段数 > 2 时改为纵向排列。

import SwiftUI

public struct ZSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: Text
    public var id: Value { value }

    public init(_ value: Value, title: LocalizedStringKey) {
        self.value = value
        self.title = Text(title)
    }

    public init(_ value: Value, verbatim title: String) {
        self.value = value
        self.title = Text(verbatim: title)
    }
}

public struct ZSegmented<Value: Hashable>: View {
    private let segments: [ZSegment<Value>]
    @Binding private var selection: Value
    private let label: LocalizedStringKey?
    @Namespace private var knob
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = ZMetrics.segmentHeight

    /// - Parameter label: 整组的 VoiceOver 名称（如 "节点来源"）。
    public init(_ segments: [ZSegment<Value>], selection: Binding<Value>, label: LocalizedStringKey? = nil) {
        self.segments = segments
        _selection = selection
        self.label = label
    }

    public var body: some View {
        let outer = ZMetrics.segmentRadius
        Group {
            if dynamicTypeSize.isAccessibilitySize && segments.count > 2 {
                VStack(spacing: 0) { items }
            } else {
                HStack(spacing: 0) { items }
            }
        }
        .padding(ZMetrics.segmentInset)
        .background(RoundedRectangle(cornerRadius: outer, style: .continuous).fill(ZTrackFill()))
        .animation(reduceMotion ? nil : ZMotion.slow, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .modifier(ZOptionalAccessibilityLabel(label: label))
    }

    private var items: some View {
        ForEach(segments) { segment in
            let isOn = segment.value == selection
            Button {
                selection = segment.value
            } label: {
                segment.title
                    .zType(.zSegment)
                    .foregroundStyle(isOn ? ZTokens.Colors.screenT1 : ZColor.t2)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ZTokens.Space.n3)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: ZMetrics.segmentKnobRadius, style: .continuous)
                                .fill(ZKnobFill())
                                .shadow(color: .black.opacity(ZMetrics.segmentShadowOpacity),
                                        radius: ZMetrics.segmentShadowRadius, y: ZMetrics.segmentShadowY)
                                .matchedGeometryEffect(id: "knob", in: knob)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// 只有在提供了名称时才设置 VoiceOver label（空字符串 label 会让 VoiceOver 读出空白容器名）。
private struct ZOptionalAccessibilityLabel: ViewModifier {
    let label: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

#if DEBUG
private struct ZSegmentedSample: View {
    @State private var source = 0
    @State private var route = "不变"
    var body: some View {
        ZSegmented([ZSegment(0, title: "订阅分组"), ZSegment(1, title: "Zephyr 优选")], selection: $source, label: "节点来源")
        ZSegmented(["不变", "直连", "视频", "其他"].map { ZSegment($0, verbatim: $0) }, selection: $route, label: "本次覆写")
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSegmentedSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSegmentedSample() } }
#Preview("强调色") { ZAccentMatrix { ZSegmentedSample() } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSegmentedSample() } }

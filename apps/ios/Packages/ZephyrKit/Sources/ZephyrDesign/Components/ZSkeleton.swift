// 骨架占位：圆角块 + 缓慢扫光（1.6s 一个周期）。Reduce Motion 下静止。
// 两种用法：`ZSkeleton(width: 120, height: 14)` 单块；`.zSkeleton(isLoading)` 把任意视图变成占位（redacted + 扫光）。

import SwiftUI

public struct ZSkeleton: View {
    private let width: CGFloat?
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = ZTokens.FontSize.sm, cornerRadius: CGFloat = ZTokens.Radius.control / 2) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ZTrackFill())
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .modifier(ZShimmer(active: true))
            .accessibilityHidden(true)
    }
}

public extension View {
    /// 加载中：内容变为占位块并扫光；VoiceOver 读 “加载中”。
    func zSkeleton(_ isLoading: Bool) -> some View {
        modifier(ZSkeletonModifier(isLoading: isLoading))
    }
}

private struct ZSkeletonModifier: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading {
            content
                .redacted(reason: .placeholder)
                .modifier(ZShimmer(active: true))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "加载中"))
        } else {
            content
        }
    }
}

/// 扫光：一条斜向高光从左到右循环；只动一个 mask 的 offset，不重建内容。
struct ZShimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, ZTokens.Colors.bgMuted, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: proxy.size.width * phase)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: ZTokens.Time.slow * 5).repeatForever(autoreverses: false)) {
                        phase = 1.4
                    }
                }
        } else {
            content
        }
    }
}

#if DEBUG
private struct ZSkeletonSample: View {
    var body: some View {
        ZCard {
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                ZSkeleton(width: 120, height: 18)
                ZSkeleton(height: 12)
                ZSkeleton(width: 200, height: 12)
            }
        }
        ZCard {
            VStack(alignment: .leading) {
                Text(verbatim: "Nebula Cloud").zType(.body)
                Text(verbatim: "8,204 个节点 · 26 天后到期").zType(.footnote)
            }
            .zSkeleton(true)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSkeletonSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSkeletonSample() } }
#Preview("强调色") { ZAccentMatrix { ZSkeleton(width: 160) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSkeletonSample() } }

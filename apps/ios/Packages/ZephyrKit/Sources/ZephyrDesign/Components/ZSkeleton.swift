// 骨架占位：圆角块 + 缓慢扫光（1.6s 一个周期）。Reduce Motion 下静止。
// 两种用法：`ZSkeleton(width: 120, height: 14)` 单块；`.zSkeleton(isLoading)` 把任意视图变成占位（redacted + 扫光）。
// 性能：内容只渲染一次——单块的扫光按自身圆角裁切；`.zSkeleton` 用 compositingGroup + sourceAtop 混合把扫光限制在
// 占位块上（不再 `.mask(content)` 把内容再画一遍）。每个实例各自一个 repeatForever 动画，长列表（> 一屏）请改用
// 列表自己的占位行（如节点列表的 CALayer 骨架），不要逐行挂 `.zSkeleton`。

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
            .modifier(ZShimmer(active: true, clip: .shape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))))
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
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
                .modifier(ZShimmer(active: true, clip: .content))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("加载中"))
        } else {
            content
        }
    }
}

/// 扫光的裁切方式。
enum ZShimmerClip {
    /// 已知形状（单块骨架）：直接按形状裁切，零额外渲染。
    case shape(RoundedRectangle)
    /// 任意内容（`.zSkeleton`）：compositingGroup 内用 sourceAtop 混合，高光只落在内容已有像素上，内容不重复渲染。
    case content
}

/// 扫光：一条高光从左到右循环；只动 overlay 的 offset，不重建内容。
struct ZShimmer: ViewModifier {
    let active: Bool
    var clip: ZShimmerClip = .content
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            applyClip(content.overlay { band })
                .onAppear {
                    withAnimation(.linear(duration: ZTokens.Time.slow * 5).repeatForever(autoreverses: false)) {
                        phase = 1.4
                    }
                }
        } else {
            content
        }
    }

    private var band: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, ZTokens.Colors.screenS4, .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 0.6)
                .offset(x: proxy.size.width * phase)
        }
        .blendMode(isContentClip ? .sourceAtop : .normal)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isContentClip: Bool {
        if case .content = clip { return true }
        return false
    }

    @ViewBuilder
    private func applyClip<V: View>(_ view: V) -> some View {
        switch clip {
        case .shape(let shape): view.clipShape(shape)
        case .content: view.compositingGroup()
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

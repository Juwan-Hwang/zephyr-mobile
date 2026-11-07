// 场景/策略组行（原型首页 `.rows .row`）：左 “AI” 17 号 + “9 个可用” 13 t3（或红色 “Claude 不可用”）；
// 右 [JP] 东京 03（15 号）+ 下方说明（“GPT、Gemini 正常”）或锁定说明（🔒 黄色锁 “Claude：US-Fixed-01”）或检测进度条。
// 左右滑切换地区时底部出现分段轨道（`.track`，当前段强调色）并带 5% 强调色底。
// 未连接时整行 55% 透明。AX 尺寸改为上下堆叠（同原型 xl）。
// 本身不带背景：放进 `ZCard(padding: 0)`，行间 `ZDivider()`；可点时包 `Button { } label: { ZGroupCard(…) }.buttonStyle(ZRowButtonStyle())`。

import SwiftUI

public enum ZGroupTone: Sendable {
    case normal, warning, danger
}

public struct ZGroupCard: View {
    private let title: String
    private let subtitle: String
    private let subtitleTone: ZGroupTone
    private let regionCode: String?
    private let exitName: String
    private let detail: String?
    private let pinned: String?
    private let progress: Double?
    private let isDimmed: Bool
    private let scrubCount: Int
    private let scrubIndex: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.zAccent) private var accent

    /// - Parameters:
    ///   - pinned: 锁定说明，如 "Claude：US-Fixed-01"（优先于 detail 显示）。
    ///   - progress: 0...1 显示检测进度条（优先于 detail/pinned）。
    ///   - scrubCount / scrubIndex: 横滑切换时的候选数与当前位置；scrubIndex 为 nil 不显示轨道。
    public init(title: String,
                subtitle: String,
                subtitleTone: ZGroupTone = .normal,
                regionCode: String?,
                exitName: String,
                detail: String? = nil,
                pinned: String? = nil,
                progress: Double? = nil,
                isDimmed: Bool = false,
                scrubCount: Int = 0,
                scrubIndex: Int? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleTone = subtitleTone
        self.regionCode = regionCode
        self.exitName = exitName
        self.detail = detail
        self.pinned = pinned
        self.progress = progress
        self.isDimmed = isDimmed
        self.scrubCount = scrubCount
        self.scrubIndex = scrubIndex
    }

    public var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n2))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: ZTokens.Space.n4))
        layout {
            VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
                Text(verbatim: title)
                    .zType(.headline)
                    .fontWeight(.regular)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                Text(verbatim: subtitle)
                    .zType(.footnote)
                    .foregroundStyle(subtitleColor)
            }
            .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
            VStack(alignment: stacked ? .leading : .trailing, spacing: ZTokens.Space.n1) {
                HStack(spacing: ZTokens.Space.n3) {
                    if let regionCode { ZFlag(regionCode, isHighlighted: scrubIndex != nil) }
                    Text(verbatim: exitName)
                        .zType(.body)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                        .lineLimit(stacked ? nil : 1)
                }
                secondary
            }
        }
        .padding(.horizontal, ZTokens.Space.n5)
        .padding(.vertical, ZTokens.Space.n5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrubIndex != nil ? accent.color.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) { scrubTrack }
        .opacity(isDimmed ? 0.55 : 1)
        .animation(ZMotion.standard, value: scrubIndex)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var secondary: some View {
        if let progress {
            ZProgressBar(value: progress, tone: .accent, label: "检测进度")
                .frame(maxWidth: ZMetrics.scanBarWidth)
        } else if let pinned {
            HStack(spacing: ZTokens.Space.n2) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(ZTokens.Colors.screenAmber.opacity(0.85))
                    .accessibilityLabel(Text(verbatim: "已锁定"))
                Text(verbatim: pinned)
            }
            .zType(.caption)
            .foregroundStyle(ZTokens.Colors.screenT3)
        } else if let detail {
            Text(verbatim: detail)
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenT3)
        }
    }

    @ViewBuilder
    private var scrubTrack: some View {
        if let scrubIndex, scrubCount > 1 {
            HStack(spacing: ZMetrics.scrubGap) {
                ForEach(0..<scrubCount, id: \.self) { i in
                    Capsule()
                        .fill(i == scrubIndex ? AnyShapeStyle(accent.color) : AnyShapeStyle(ZTokens.Colors.screenHl2))
                        .frame(height: ZMetrics.scrubHeight)
                }
            }
            .padding(.horizontal, ZTokens.Space.n5)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private var subtitleColor: Color {
        switch subtitleTone {
        case .normal: return ZTokens.Colors.screenT3
        case .warning: return ZTokens.Colors.screenAmber
        case .danger: return ZTokens.Colors.screenRed
        }
    }
}

#if DEBUG
private struct ZGroupCardSample: View {
    var body: some View {
        ZCard(padding: 0) {
            VStack(spacing: 0) {
                ZGroupCard(title: "AI", subtitle: "9 个可用", regionCode: "JP", exitName: "东京 03", pinned: "Claude：US-Fixed-01")
                ZDivider()
                ZGroupCard(title: "AI", subtitle: "Claude 不可用", subtitleTone: .danger, regionCode: "SG", exitName: "新加坡 02", detail: "GPT、Gemini 正常")
                ZDivider()
                ZGroupCard(title: "视频", subtitle: "22 个可用", regionCode: "HK", exitName: "香港 HKT", detail: "Netflix 完整片库", scrubCount: 6, scrubIndex: 2)
                ZDivider()
                ZGroupCard(title: "其他", subtitle: "订阅分组", regionCode: "TW", exitName: "TW-Fixed-01", progress: 0.27)
                ZDivider()
                ZGroupCard(title: "其他", subtitle: "订阅分组", regionCode: "TW", exitName: "TW-Fixed-01", isDimmed: true)
            }
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZGroupCardSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZGroupCardSample() } }
#Preview("强调色") { ZAccentMatrix { ZCard(padding: 0) { ZGroupCard(title: "视频", subtitle: "22 个可用", regionCode: "HK", exitName: "香港 HKT", scrubCount: 5, scrubIndex: 1) } } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZGroupCardSample() } }

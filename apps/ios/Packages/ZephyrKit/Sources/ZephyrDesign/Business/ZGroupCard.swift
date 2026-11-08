// 场景/策略组行（原型首页 `.rows .row`，数值均取自 index.html）：
//   行 padding 15 16、两栏间距 12、垂直居中；按下 rgba(255,255,255,.025)（screen.pressed）。
//   左：名称 17 / 字距 −0.01em；下方 3pt 处状态 13 t3（或红色 “Claude 不可用”）；检测中时状态下方 9pt 一条 96×2 进度条（--hl 轨道 + 强调色）。
//   右：`.ex` [JP] 东京 03（15 号，间距 8）；下方 5pt 处 `.pin` 12 t3：🔒（琥珀 .85，间距 6）锁定说明，或纯文字备注（“Netflix 完整片库”）。
//   左右滑切换地区：底部 `.track`（3 高、段距 3、圆角 2、--hl2 / 当前段强调色，左右 16）+ 5% 强调色底；地区码 `.cc.tick` 跳动。
//   未连接时整行 55% 透明。大字体（≥ xxxLarge，同原型 xl 与首页 SceneRow）改为上下堆叠、左对齐、间距 6，文字不截断。
// 本身不带背景：放进 `ZCard(padding: 0)`，行间 `ZDivider()`。
// 可点：`Button { } label: { ZGroupCard(…) }.buttonStyle(ZRowButtonStyle())`；
// 自己处理手势（如首页横滑）时传 `isPressed` / `scrubIndex` / `isFlagHighlighted`，并在外层用自定义无障碍标签覆盖（`.accessibilityElement(children: .ignore)`）。

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
    private let isProbing: Bool
    private let isPressed: Bool
    private let isFlagHighlighted: Bool?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.zAccent) private var accent

    /// - Parameters:
    ///   - subtitle: 名称下方状态（“9 个可用” / “订阅分组” / “4 个可用 · 检测中”）。
    ///   - pinned: 锁定说明，如 "Claude：US-Fixed-01"（优先于 detail 显示，带琥珀小锁）。
    ///   - detail: 右侧第二行纯文字备注（`.pin` 无锁版本）。
    ///   - progress: 0...1 时在状态下方显示确定进度条（原型 scan）。
    ///   - isProbing: progress 为 nil 时显示不确定（往复流动）进度条。
    ///   - scrubCount / scrubIndex: 横滑切换时的候选数与当前位置；scrubIndex 为 nil 不显示轨道。
    ///   - isPressed: 自定义手势的按下态（用 ZRowButtonStyle 时不用传）。
    ///   - isFlagHighlighted: 地区码跳动；nil 时跟随 “正在横滑”（scrubIndex != nil）。
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
                scrubIndex: Int? = nil,
                isProbing: Bool = false,
                isPressed: Bool = false,
                isFlagHighlighted: Bool? = nil) {
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
        self.isProbing = isProbing
        self.isPressed = isPressed
        self.isFlagHighlighted = isFlagHighlighted
    }

    /// 与首页 SceneRow 相同的堆叠阈值（原型 xl 在非 AX 尺寸就开始堆叠）。
    public static func isStacked(_ size: DynamicTypeSize) -> Bool { size >= .xxxLarge }

    public var body: some View {
        let stacked = Self.isStacked(dynamicTypeSize)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZMetrics.groupStackGap))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: ZMetrics.groupRowGap))
        layout {
            leading
                .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
            trailing(stacked: stacked)
        }
        .padding(.vertical, ZMetrics.groupRowVertical)
        .padding(.horizontal, ZMetrics.groupRowHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .bottom) { scrubTrack }
        .opacity(isDimmed ? 0.55 : 1)
        .animation(ZMotion.standard, value: scrubIndex)
        .accessibilityElement(children: .combine)
    }

    // MARK: 左栏

    private var leading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .zType(.headline)
                .fontWeight(.regular)
                .tracking(ZTokens.TypeStyle.headline.size * ZMetrics.rowTitleTracking)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Text(verbatim: subtitle)
                .zType(.footnote)
                .foregroundStyle(subtitleColor)
                .padding(.top, ZMetrics.groupMetaTop)
            if let progress {
                ZProgressBar(value: progress, tone: .accent, label: "检测进度")
                    .frame(width: ZMetrics.probeBarWidth)
                    .padding(.top, ZMetrics.probeBarTop)
            } else if isProbing {
                ZGroupProbeBar()
                    .frame(width: ZMetrics.probeBarWidth)
                    .padding(.top, ZMetrics.probeBarTop)
            }
        }
    }

    // MARK: 右栏

    private func trailing(stacked: Bool) -> some View {
        VStack(alignment: stacked ? .leading : .trailing, spacing: 0) {
            HStack(spacing: ZTokens.Space.n3) {
                if let regionCode { ZFlag(regionCode, isHighlighted: isFlagHighlighted ?? (scrubIndex != nil)) }
                Text(verbatim: exitName)
                    .zType(.zRowValue)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(stacked ? nil : 1)
                    .contentTransition(.opacity)
            }
            secondary(stacked: stacked)
        }
        .multilineTextAlignment(stacked ? .leading : .trailing)
    }

    @ViewBuilder
    private func secondary(stacked: Bool) -> some View {
        if let pinned {
            HStack(spacing: ZMetrics.groupPinGap) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(ZTokens.Colors.screenAmber.opacity(ZMetrics.pinIconOpacity))
                    .accessibilityLabel(Text(verbatim: "已锁定"))
                Text(verbatim: pinned)
                    .lineLimit(stacked ? nil : 1)
            }
            .zType(.caption)
            .foregroundStyle(ZTokens.Colors.screenT3)
            .padding(.top, ZMetrics.groupPinTop)
        } else if let detail {
            Text(verbatim: detail)
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .lineLimit(stacked ? nil : 1)
                .padding(.top, ZMetrics.groupPinTop)
        }
    }

    // MARK: 横滑轨道 / 背景

    @ViewBuilder
    private var scrubTrack: some View {
        if let scrubIndex, scrubCount > 1 {
            HStack(spacing: ZMetrics.scrubGap) {
                ForEach(0..<scrubCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: ZMetrics.scrubRadius, style: .continuous)
                        .fill(i == scrubIndex ? AnyShapeStyle(accent.color) : AnyShapeStyle(ZTokens.Colors.screenHl2))
                        .frame(height: ZMetrics.scrubHeight)
                }
            }
            .padding(.horizontal, ZMetrics.groupRowHorizontal)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private var rowBackground: Color {
        if scrubIndex != nil { return accent.color.opacity(ZMetrics.scrubTint) }
        return isPressed ? ZTokens.Colors.screenPressed : Color.clear
    }

    private var subtitleColor: Color {
        switch subtitleTone {
        case .normal: return ZTokens.Colors.screenT3
        case .warning: return ZTokens.Colors.screenAmber
        case .danger: return ZTokens.Colors.screenRed
        }
    }
}

/// 不确定进度：强调色短条在 --hl 轨道里往复（Reduce Motion 下静止在左侧）。
private struct ZGroupProbeBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(ZTokens.Colors.screenHl)
                Capsule(style: .continuous).fill(ZAccentStyle())
                    .frame(width: w * 0.3)
                    .offset(x: reduceMotion ? 0 : phase * w * 0.7)
            }
        }
        .frame(height: ZMetrics.barThin)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(ZTokens.Easing.easeInOut(duration: ZTokens.Time.slow * 3).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "检测中"))
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
                ZGroupCard(title: "AI", subtitle: "4 个可用", regionCode: "SG", exitName: "新加坡 02", pinned: "Claude：US-Fixed-01", progress: 0.27)
                ZDivider()
                ZGroupCard(title: "AI", subtitle: "4 个可用 · 检测中", regionCode: "SG", exitName: "新加坡 02", isProbing: true, isPressed: true)
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

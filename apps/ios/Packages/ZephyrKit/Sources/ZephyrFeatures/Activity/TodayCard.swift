// 今日卡片本体（原型 14 `#shareCard`，截图 today.png / today-dawn.png / today-mist.png）：
//   流线背景（WindArtCanvas）
//   11月6日 · 星期五
//   1.8 GB
//   4 个地区 · 6 小时在线 · 38 ms 最快
//   ─────────────
//   Zephyr                       今日
// 页面里随宽度缩放（346:500）；分享 / 存储时用 ImageRenderer 按 346×500 ×3 导出（animated = false）。
// 卡片是固定比例的图片，字号封顶 xLarge（大字体用户通过 VoiceOver 标签获得完整信息）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct TodayCard: View {
    let usage: UsageSummary
    let dateText: String
    let theme: TodayTheme
    var animated = true

    private var total: (value: String, unit: String) { ZFormat.bytesParts(usage.todayBytes) }
    private var hours: Int64 { usage.onlineMillisToday / 3_600_000 }
    private var fastest: String { usage.fastestLatencyMs.map { $0 < 0 ? "—" : "\($0)" } ?? "—" }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HMetrics.todayCardRadius, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            theme.background
            WindArtCanvas(theme: theme, hourly: usage.hourly, animated: animated)
            info
        }
        .aspectRatio(HMetrics.todayCardAspect, contentMode: .fit)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.rule, lineWidth: HMetrics.hairline / 2) }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityAddTraits(.isImage)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: dateText)
                .zType(.footnote)
                .foregroundStyle(theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n2) {
                Text(verbatim: total.value)
                    .foregroundStyle(theme.primary)
                    .zDisplay(.hero, weight: .thin)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: total.unit)
                    .zType(.headline).fontWeight(.regular)
                    .foregroundStyle(theme.secondary)
            }
            .padding(.top, ZTokens.Space.n1)
            HStack(alignment: .top, spacing: ZTokens.Space.n6) {
                stat("\(usage.regionsToday)", ZL.tr("个地区"))
                stat("\(hours)", ZL.tr("小时在线"))
                stat(fastest, ZL.tr("ms 最快"))
            }
            .padding(.top, ZTokens.Space.n5)
            Rectangle().fill(theme.rule).frame(height: HMetrics.hairline / 2)
                .padding(.top, ZTokens.Space.n6)
            HStack {
                ZBrandMark(.lockup)
                    .frame(height: HMetrics.todayLockupHeight)
                    .foregroundStyle(theme.primary)
                Spacer(minLength: ZTokens.Space.n3)
                Text("今日").zType(.caption).foregroundStyle(theme.tertiary)
            }
            .padding(.top, ZTokens.Space.n4)
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(stops: [.init(color: theme.scrim.opacity(0), location: 0),
                                   .init(color: theme.scrim, location: 0.38)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
            Text(verbatim: value)
                .foregroundStyle(theme.primary)
                .zDisplay(.compact, weight: .light)
                .lineLimit(1)
            Text(verbatim: label)
                .zType(.caption)
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
        }
    }

    private var a11y: String {
        ZL.s("今日 %1$@ %2$@，%3$@ 个地区，%4$@ 小时在线，最快 %5$@ 毫秒。%6$@", total.value, total.unit, "\(usage.regionsToday)", "\(hours)", fastest, dateText)
    }
}

#Preview("夜 / 晨 / 雾") {
    let u = UsageSummary(todayBytes: 1_800_000_000, regionsToday: 4, onlineMillisToday: 6 * 3_600_000, fastestLatencyMs: 38,
                         hourly: (0..<24).map { Int64(($0 * 37) % 11) * 10_000_000 })
    return ScrollView {
        VStack(spacing: ZTokens.Space.n6) {
            ForEach(TodayTheme.allCases) { TodayCard(usage: u, dateText: "11月6日 · 星期五", theme: $0) }
        }
        .padding(HMetrics.homeInset)
    }
    .zPageBackground()
}

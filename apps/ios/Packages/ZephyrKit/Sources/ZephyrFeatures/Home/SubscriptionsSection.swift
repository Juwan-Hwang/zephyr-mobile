// 首页"订阅"区（原型 `.rows.subs`）：标题右侧"今日 1.8 GB ›"打开今日卡片；
// 卡片列出前两个订阅：名称 + 用量条，右侧剩余流量 + 到期（7 天内到期为警告色）。轻点 → 订阅页。
// 字号按原型 `.row .n` 17 / `.row .m` 13；到期 1–6 天内用星期（"周一到期"，global.png，REVIEW H-P2-6）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct SubscriptionsSection: View {
    @Environment(AppModel.self) private var model
    static let featuredCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZSectionHeader("订阅", trailing: todayText) { model.present(.today) }
                .homeSectionInsets()
            ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
                VStack(spacing: 0) {
                    let featured = Array(model.subscriptions.prefix(Self.featuredCount))
                    if featured.isEmpty {
                        Button { model.push(.subscriptions) } label: {
                            HStack {
                                Text("添加订阅").zType(.body).foregroundStyle(ZAccentStyle())
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(ZAccentStyle())
                            }
                            .padding(.vertical, HMetrics.rowVertical)
                            .padding(.horizontal, HMetrics.rowHorizontal)
                        }
                        .buttonStyle(ZRowButtonStyle())
                    }
                    ForEach(Array(featured.enumerated()), id: \.element.id) { i, sub in
                        if i > 0 { ZDivider() }
                        Button { model.push(.subscriptions) } label: {
                            SubscriptionRow(sub: sub, now: model.now())
                        }
                        .buttonStyle(ZRowButtonStyle())
                    }
                }
            }
            .padding(.horizontal, HMetrics.cardInset)
        }
    }

    private var todayText: String {
        guard let u = model.usage else { return ZL.tr("今日") }
        return ZL.s("今日 %@", ZFormat.bytes(u.todayBytes))
    }
}

@MainActor
private struct SubscriptionRow: View {
    let sub: Subscription
    let now: Int64

    private static let weekMillis: Int64 = 7 * 86_400_000

    private var warn: Bool {
        guard let e = sub.expiresAt else { return false }
        return e - now < Self.weekMillis
    }

    private var used: Double? {
        guard let u = sub.usedBytes, let t = sub.totalBytes, t > 0 else { return nil }
        return min(1, max(0, Double(u) / Double(t)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: ZTokens.Space.n5) {
            VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                Text(verbatim: sub.name)
                    .zType(.headline).fontWeight(.regular)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                    .lineLimit(1)
                if let used {
                    ZProgressBar(value: used, tone: warn ? .warning : .neutral)
                }
            }
            VStack(alignment: .trailing, spacing: ZTokens.Space.n1) {
                if let r = sub.remainingBytes {
                    Text(verbatim: ZFormat.bytes(r))
                        .zType(.headline, monospacedDigits: true).fontWeight(.regular)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                }
                if let e = sub.expiresAt {
                    Text(verbatim: HFormat.homeExpiry(e, now: now))
                        .zType(.footnote)
                        .foregroundStyle(warn ? ZTokens.Colors.screenAmber : ZColor.t3)
                }
            }
        }
        .padding(.vertical, HMetrics.rowVertical)
        .padding(.horizontal, HMetrics.rowHorizontal)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
    }

    private var a11y: String {
        var parts = [sub.name]
        if let r = sub.remainingBytes { parts.append(ZL.s("剩余 %@", ZFormat.bytes(r))) }
        if let used { parts.append(ZL.f("已用 %lld%%", Int64((used * 100).rounded()))) }
        if let e = sub.expiresAt { parts.append(HFormat.homeExpiry(e, now: now)) }
        return parts.joined(separator: "，")
    }
}

#Preview {
    HPreview(model: .preview()) { ScrollView { SubscriptionsSection() } }
}

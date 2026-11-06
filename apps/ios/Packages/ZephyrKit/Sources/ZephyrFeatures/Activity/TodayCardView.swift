// TodayCardView —— 今日用量卡（契约 UsageSummary）。
// [A] 先补可用实现以解除编译；B 可按原型 Today 页细化。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct TodayCardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let u = model.usage {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ZFormat.bytes(u.todayBytes))
                                    .font(.system(size: 44, weight: .light).monospacedDigit())
                                    .foregroundStyle(ZTokens.Colors.textPrimary)
                                Text("\(u.regionsToday) 个地区 · \(ZFormat.duration(u.onlineMillisToday)) 在线 · \(ZFormat.latency(u.fastestLatencyMs)) 最快")
                                    .font(.subheadline)
                                    .foregroundStyle(ZTokens.Colors.textSecondary)
                            }
                            HourlyBars(hourly: u.hourly)
                                .frame(height: 96)
                                .accessibilityLabel("今日每小时用量")
                        }
                        .padding(20)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct HourlyBars: View {
    let hourly: [Int64]

    var body: some View {
        let peak = max(hourly.max() ?? 1, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(hourly.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ZTokens.Colors.textSecondary)
                        .frame(height: max(2, geo.size.height * CGFloat(v) / CGFloat(peak)))
                }
            }
        }
    }
}

// 实时活动：锁屏卡片（原型 shots/lock.png）与灵动岛紧凑 / 最小 / 展开态（shots/hs.png 顶部）。
// 计时器用 frozenNow 渲染成静态 “2:14:07”，否则 Text(.timer) 每次运行都不同。

import SwiftUI
import XCTest
import ZephyrDesign

@MainActor
final class LiveActivitySnapshotTests: XCTestCase {

    private static let lockWidth: CGFloat = 369   // 393 - 两侧 12

    private func lockCard(state: ZephyrActivityAttributes.ContentState, accent: ZTokens.Accent) -> some View {
        LiveActivityLockView(state: state, accent: accent.color, frozenNow: SnapshotFixtures.now)
            .frame(width: Self.lockWidth)
            .background(ZTokens.Colors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
            .padding(12)
    }

    func testLockScreenCard() async {
        for variant in ZSnapshotVariant.standardPlusAccent(.orange) {
            await zAssertSnapshot(of: lockCard(state: SnapshotFixtures.activity, accent: variant.accent),
                                  named: "lock-\(variant.name)", variant: variant, layout: .fitWidth(393))
        }
    }

    func testLockScreenCardEdgeCases() async {
        let edgy = ZephyrActivityAttributes.ContentState(SnapshotFixtures.edgyScenes)
        await zAssertSnapshot(of: lockCard(state: edgy, accent: .blue),
                              named: "lock-edge-dark", variant: .dark, layout: .fitWidth(393))
        let connecting = ZephyrActivityAttributes.ContentState(status: .connecting, mode: .rule, downBps: 0, upBps: 0,
                                                               scenes: [], connectedSince: nil)
        await zAssertSnapshot(of: lockCard(state: connecting, accent: .blue),
                              named: "lock-connecting-dark", variant: .dark, layout: .fitWidth(393))
    }

    /// 灵动岛永远是黑底；只验证深色 + AX5 + 一个强调色。
    func testDynamicIsland() async {
        let state = SnapshotFixtures.activity
        for variant in [ZSnapshotVariant.dark, .darkAX5, .accentSample(.green)] {
            let accent = variant.accent.color
            let island = VStack(spacing: ZTokens.Space.n5) {
                // 紧凑态
                HStack {
                    IslandCompactLeading(accent: accent)
                    Spacer()
                    IslandCompactTrailing(state: state)
                }
                .padding(.horizontal, ZTokens.Space.n4)
                .frame(width: 250, height: 37)
                .background(Capsule().fill(.black))
                // 最小态
                IslandMinimal(accent: accent)
                    .frame(width: 37, height: 37)
                    .background(Circle().fill(.black))
                // 展开态
                VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                    HStack {
                        IslandCompactLeading(accent: accent)
                        Text("Zephyr").zType(.headline).foregroundStyle(.white)
                        Spacer()
                        ConnectionTimer(since: state.connectedSince, frozenNow: SnapshotFixtures.now)
                            .zType(.headline, monospacedDigits: true)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    IslandExpandedBottom(state: state)
                }
                .padding(ZTokens.Space.n5)
                .frame(width: 369)
                .background(RoundedRectangle(cornerRadius: ZTokens.Layout.sheetRadius, style: .continuous).fill(.black))
            }
            .padding(ZTokens.Space.n4)
            .environment(\.colorScheme, .dark)
            await zAssertSnapshot(of: island, named: "island-\(variant.name)", variant: variant, layout: .fitWidth(393))
        }
    }
}
